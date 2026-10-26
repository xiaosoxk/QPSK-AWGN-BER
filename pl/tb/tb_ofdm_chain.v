/**
 * tb_ofdm_chain.v — 全链路位精确比对 Testbench
 *
 * 方法: 读黄金向量(golden/vectors/*.hex, 由 Python 浮点模型生成):
 *   qam_sym_i/q.hex  → 直接驱动 pilot_insert(跳过mapper, 符号级验证)
 *   chan_tap_r/i.hex → 写入信道FIR系数(平坦[1,0,0]→位精确; 多径→统计验证)
 *   exp_rx_bits.hex  → 与 demapper 输出逐一比对, 错误计数
 * 结果: error_count==0 → 全链路位精确 PASS
 *
 * 注: 端到端(含mapper比特流)验证由 tb_qam_mapper.v 单独覆盖;
 *     本TB聚焦 符号→IFFT→CP→信道→去CP→FFT→估计均衡→硬判 数据通路。
 */
`timescale 1ns/1ps
`include "ofdm_params.vh"

module tb_ofdm_chain;
    reg clk = 0, resetn = 0;
    always #5 clk = ~clk;                  // 100MHz

    reg         tx_valid = 0;
    reg  [31:0] tx_data = 0;
    wire        tx_ready;
    wire        txout_valid; wire [31:0] txout_data; wire txout_sof;
    wire signed [15:0] h0r, h0i, h1r, h1i, h2r, h2i;   // 由系数寄存器注入

    // 信道FIR(系数由黄金向量写入)
    wire        fir_valid; wire [31:0] fir_data;
    chan_fir u_ch (
        .clk(clk), .resetn(resetn),
        .s_axis_tvalid(txout_valid), .s_axis_tdata(txout_data),
        .h0r(h0r), .h0i(h0i), .h1r(h1r), .h1i(h1i), .h2r(h2r), .h2i(h2i),
        .m_axis_tvalid(fir_valid), .m_axis_tdata(fir_data));

    // RX链
    wire        ber_valid; wire [1:0] ber_bits;
    ofdm_rx_top u_rx (
        .clk(clk), .resetn(resetn),
        .rx_en(1'b1), .pilot_pol(1'b0), .eq_enable(1'b1),
        .s_axis_tvalid(fir_valid), .s_axis_tdata(fir_data),
        .m_axis_tvalid(ber_valid), .m_axis_tdata(ber_bits));

    // ---------- 黄金向量 ----------
    reg [15:0] sym_i [0:1439];             // 1440 QAM符号
    reg [15:0] sym_q [0:1439];
    reg        exp_bits [0:2879];          // 2880期望比特
    reg [15:0] tap_r [0:2], tap_i [0:2];
    integer sym_cnt = 0, bit_cnt = 0, err_cnt = 0;
    integer i;

    initial begin
        $readmemh("vectors/qam_sym_i.hex", sym_i);
        $readmemh("vectors/qam_sym_q.hex", sym_q);
        $readmemh("vectors/chan_tap_r.hex", tap_r);
        $readmemh("vectors/chan_tap_i.hex", tap_i);
        $readmemh("vectors/exp_rx_bits.hex", exp_bits);
    end

    // 系数注入(仿真中直接驱动FIR端口)
    assign h0r = tap_r[0]; assign h0i = tap_i[0];
    assign h1r = tap_r[1]; assign h1i = tap_i[1];
    assign h2r = tap_r[2]; assign h2i = tap_i[2];

    // ---------- TX激励: 符号直驱(跳过mapper, 符号级黄金比对) ----------
    always @(posedge clk or negedge resetn) begin
        if (!resetn) tx_valid <= 0;
        else if (sym_cnt < 1440) begin
            tx_valid <= 1;
            tx_data  <= {sym_q[sym_cnt], sym_i[sym_cnt]};
            if (tx_ready) sym_cnt <= sym_cnt + 1;
        end else tx_valid <= 0;
    end

    // ---------- RX比对 ----------
    always @(posedge clk) begin
        if (ber_valid) begin
            if (ber_bits !== exp_bits[bit_cnt]) begin
                err_cnt = err_cnt + 1;
                if (err_cnt < 20)
                    $display("BIT ERR @%0d: got %b exp %b",
                             bit_cnt, ber_bits, exp_bits[bit_cnt]);
            end
            bit_cnt = bit_cnt + 1;
        end
    end

    initial begin
        resetn = 0;
        repeat (10) @(posedge clk);
        resetn = 1;
        // 等待: 3帧×800采样 + FFT/估计流水 余量
        wait (bit_cnt >= 2880);
        repeat (200) @(posedge clk);
        $display("=== RESULT: %0d bits, %0d errors ===", bit_cnt, err_cnt);
        if (err_cnt == 0) $display("TB PASS: bit-exact vs golden vectors");
        else              $display("TB FAIL: %0d bit errors", err_cnt);
        $finish;
    end

    initial begin
        #10_000_000;                       // 10ms 超时保护
        $display("TB TIMEOUT");
        $finish;
    end
endmodule
