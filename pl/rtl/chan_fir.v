/**
 * chan_fir.v — 3径复数FIR多径信道模拟器（系数PS经AXI-Lite可写）
 * y[n] = x[n]·h0 + x[n-1]·h1 + x[n-2]·h2
 * 复乘展开: 每径4实乘2实加 → 12个DSP48; 系数Q1.14, 输出Q1.14(截位注释)
 * 延迟抽头: 复数乘法结果取高16位(等效除以2^14)
 */
`timescale 1ns/1ps
`include "ofdm_params.vh"

module chan_fir (
    input  wire        clk, resetn,
    input  wire        s_axis_tvalid,
    input  wire [31:0] s_axis_tdata,        // {Q,I} Q1.14
    // 信道系数(PS经AXI-Lite写入): Q1.14
    input  wire signed [15:0] h0r, h0i, h1r, h1i, h2r, h2i,
    output reg         m_axis_tvalid,
    output reg [31:0]  m_axis_tdata
);
    // 复数乘宏: (ar+jai)(br+jbi) = (ar·br - ai·bi) + j(ar·bi + ai·br), 结果Q2.28→Q1.14取[29:14]
    `define CMUL(ar, ai, br, bi, re, im) \
        wire signed [31:0] re = ar*br - ai*bi; \
        wire signed [31:0] im = ar*bi + ai*br;

    // 抽头延迟线
    reg signed [15:0] d0r, d0i, d1r, d1i, d2r, d2i;

    `CMUL(s_axis_tdata[15:0], s_axis_tdata[31:16], h0r, h0i, m0r, m0i)
    `CMUL(d0r, d0i, h1r, h1i, m1r, m1i)
    `CMUL(d1r, d1i, h2r, h2i, m2r, m2i)

    wire signed [33:0] sum_r = m0r + m1r + m2r;
    wire signed [33:0] sum_i = m0i + m1i + m2i;

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            d0r <= 0; d0i <= 0; d1r <= 0; d1i <= 0; d2r <= 0; d2i <= 0;
            m_axis_tvalid <= 0; m_axis_tdata <= 0;
        end else begin
            d2r <= d1r; d2i <= d1i;            // 延迟移位
            d1r <= d0r; d1i <= d0i;
            d0r <= s_axis_tdata[15:0];
            d0i <= s_axis_tdata[31:16];
            m_axis_tvalid <= s_axis_tvalid;
            // Q2.28 → Q1.14: 取[29:14], 带16bit饱和(简化: 直接截位, 溢出由系数缩放避免)
            m_axis_tdata[15:0]  <= sum_r[29:14];
            m_axis_tdata[31:16] <= sum_i[29:14];
        end
    end
endmodule
