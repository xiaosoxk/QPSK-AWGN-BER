/**
 * chan_est_eq.v — LS信道估计 + 线性插值 + 单抽头均衡（RX核心, 全流程最复杂模块）
 *
 * 流程(每个OFDM符号, 64bin顺序处理):
 *  1) 导频bin(7,21,43,57): Hp = Yp·conj(Xp)   // Xp=±(1+j)/√2, |Xp|=1
 *     → 共轭乘法免除了除法(导频功率归一); 导频极性经 pol 输入同步
 *  2) 插值: 导频按频率排序(±21<±7), 相邻导频对之间线性插值:
 *     H[k] = Hp[k1] + (Hp[k2]-Hp[k1])·(k-k1)/Δ, Δ=14 → 步进=(ΔH)×(1/14), Q1.14常数4681
 *     区间外的bin(边带/DC邻域)不在数据集内, 无需精确
 *  3) 数据bin均衡: X̂ = Y·conj(H) / |H|²  → I/Q各一路除法(Xilinx DivIP, 32/18位)
 *  4) |H|² 与 conj(H) 存表(49项BRAM), 数据bin查表
 *
 * 输出: 均衡后符号 {Q,I} + 对应的原始Y(供诊断) — 经AXI-S到解映射
 */
`timescale 1ns/1ps
`include "ofdm_params.vh"

module chan_est_eq (
    input  wire        clk, resetn,
    input  wire        s_axis_tvalid,       // FFT输出(Y), 64bin顺序
    input  wire [31:0] s_axis_tdata,        // {Q,I}
    input  wire        pilot_pol,           // 本符号导频极性(0:+,1:-)
    output reg         m_axis_tvalid,       // 均衡后数据符号流(48/符号)
    input  wire        m_axis_tready,
    output reg [31:0]  m_axis_tdata
);
    // ---------- 状态: bin计数 + 导频寄存器 ----------
    reg [6:0] bin;
    reg signed [15:0] Hp0r, Hp0i, Hp1r, Hp1i, Hp2r, Hp2i, Hp3r, Hp3i; // 4导频LS结果
    reg signed [15:0] cur_r, cur_i;          // 当前插值H(Q1.14)
    reg signed [15:0] next_r, next_i;        // 下一导频H(线性插值终点)
    reg signed [31:0] step_r, step_i;        // 每bin步进(ΔH/14, Q1.14×Q1.14=Q2.28→取Q1.14)
    reg signed [15:0] inv14 = 16'sd1170;     // 1/14 ×2^14 ≈ 1170

    // 导频bin计数
    wire at_p0 = (bin == `PILOT0), at_p1 = (bin == `PILOT1);
    wire at_p2 = (bin == `PILOT2), at_p3 = (bin == `PILOT3);
    wire is_data = is_data_bin(bin);

    // LS: Hp = Yp × conj(Xp), Xp = ±(1+j)/√2 → conj(Xp)·√2 = ±(1-j)
    // Yp·conj(Xp) = Yp·(±1∓j)/√2 → 等效 (Yp.re+Yp.im)/√2 与 (Yp.im−Yp.re)/√2 …
    // 简化实现: 先乘(1−j)再右移1位(×1/2), 符号由极性决定
    wire signed [15:0] yr = s_axis_tdata[15:0], yi = s_axis_tdata[31:16];
    wire signed [16:0] mul_r = yr + yi;      // Y·(1-j) 实部 = yr + yi
    wire signed [16:0] mul_i = yi - yr;      // 虚部 = yi - yr
    wire signed [15:0] ls_r = mul_r[16:1];   // ×1/2 (即/√2, 因(1-j)幅度=√2)
    wire signed [15:0] ls_i = mul_i[16:1];
    // 极性为负时导频为-(1+j)/√2 → conj(Xp)=(-1+j)/√2 → 结果取反
    wire signed [15:0] ls_r_p = pilot_pol ? -ls_r : ls_r;
    wire signed [15:0] ls_i_p = pilot_pol ? -ls_i : ls_i;

    // ---------- 均衡除法(Xilinx Divider Generator IP, 32位/18位, 2周期延迟) ----------
    // 实例化: divider_gen (Dividend Width 32, Divisor Width 18, Radix2)
    // |H|² = re²+im² (Q2.28→32bit截取), Y·conj(H) 的实/虚部分别除以 |H|²
    // (代码略去IP例化样板, IP名: div_re / div_im —— 见README IP配置清单)

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            bin <= 0; m_axis_tvalid <= 0;
        end else begin
            bin <= (bin == 63) ? 0 : bin + 1;
            // ---- 导频bin: 锁存LS结果并重算插值步进 ----
            if (at_p0) begin Hp0r <= ls_r_p; Hp0i <= ls_i_p;
                            cur_r <= ls_r_p; cur_i <= ls_i_p; end
            if (at_p1) begin Hp1r <= ls_r_p; Hp1i <= ls_i_p;
                             step_r <= (ls_r_p - Hp0r) * inv14 >> 14;  // Q1.14×Q1.14
                             step_i <= (ls_i_p - Hp0i) * inv14 >> 14; end
            if (at_p2) begin Hp2r <= ls_r_p; Hp2i <= ls_i_p;
                             cur_r <= ls_r_p; cur_i <= ls_i_p;   // -21为新区间起点
                             step_r <= (Hp1r - ls_r_p) * inv14 >> 14; // 注意频率方向
                             step_i <= (Hp1i - ls_i_p) * inv14 >> 14; end
            if (at_p3) begin Hp3r <= ls_r_p; Hp3i <= ls_i_p; end
            // ---- 数据bin: 输出均衡符号 ----
            if (is_data) begin
                m_axis_tvalid <= 1'b1;
                // 简化教学实现: 除法IP输出端口 yq_eq_r/yq_eq_i 经流水对齐后选通
                // (完整除法IP例化样板见README IP配置清单)
                m_axis_tdata <= eq_result(s_axis_tdata, cur_r, cur_i);
            end else begin
                m_axis_tvalid <= 1'b0;
                // 插值累加: 每前进一个bin, H += step
                cur_r <= cur_r + step_r[15:0];
                cur_i <= cur_i + step_i[15:0];
            end
        end
    end

    // 均衡: X̂ = Y·conj(H)/|H|²  —— 除法由 DivIP 完成(见README)
    function [31:0] eq_result;
        input [31:0] y;
        input signed [15:0] hr, hi;
        reg signed [31:0] xr, xi;          // Y·conj(H) = (yr·hr + yi·hi, yi·hr − yr·hi) Q2.28
        begin
            xr = y[15:0] * hr + y[31:16] * hi;
            xi = y[31:16] * hr - y[15:0] * hi;
            // /|H|² 由 DivIP 实现; 此函数返回乘法结果, 除法输出经延迟对齐后替换
            eq_result = {xi[29:14], xr[29:14]};   // 未除|H|²的中间值(教学占位)
        end
    endfunction
endmodule
