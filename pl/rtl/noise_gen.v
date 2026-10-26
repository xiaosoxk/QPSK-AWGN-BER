/**
 * noise_gen.v — 近高斯白噪声发生器（12路LFSR均匀和近似高斯, 方差由PS寄存器设定）
 * 原理: 中心极限定理, sum of 12×U(-1,1) 近似 N(0,1); LFSR提供伪随机均匀序列
 * 输出Q1.14: noise = (sum/12) × variance_reg
 */
`timescale 1ns/1ps
module noise_gen (
    input  wire        clk, resetn,
    input  wire        en,                  // 使能(每个采样节拍)
    input  wire [15:0] var_scale,           // 方差缩放(Q1.14), PS可写
    output reg signed [15:0] noise_i,
    output reg signed [15:0] noise_q
);
    reg [31:0] lfsr1 = 32'hACE1_2345, lfsr2 = 32'hDEAD_BEEF;

    function [15:0] lfsr_step;             // 16位最大长度LFSR
        input [15:0] l;
        begin
            lfsr_step = {l[14:0], l[15] ^ l[13] ^ l[12] ^ l[10]};
        end
    endfunction

    reg signed [15:0] acc_i, acc_q;        // 12次采样累加
    reg [3:0] cnt;

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            lfsr1 <= 32'hACE1_2345; lfsr2 <= 32'hDEAD_BEEF;
            cnt <= 0; acc_i <= 0; acc_q <= 0;
            noise_i <= 0; noise_q <= 0;
        end else if (en) begin
            lfsr1 <= {lfsr_step(lfsr1[15:0]), lfsr1[31:16]};
            lfsr2 <= lfsr2 + 1;
            acc_i <= acc_i + lfsr1[15:0] - 16'sd32768;   // U(-32768,32767)
            acc_q <= acc_q + lfsr2[15:0] - 16'sd32768;
            cnt <= cnt + 1;
            if (cnt == 11) begin
                cnt <= 0;
                // sum/12 ≈ N(0, 32768/√12) → 缩放: ×var_scale×(1/(32768/√12))/2^14
                noise_i <= acc_i * var_scale >>> 14;
                noise_q <= acc_q * var_scale >>> 14;
                acc_i <= 0; acc_q <= 0;
            end
        end
    end
endmodule
