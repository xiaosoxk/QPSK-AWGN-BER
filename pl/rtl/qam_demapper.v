/**
 * qam_demapper.v — QPSK 硬判解映射 (均衡后符号 → 2bit/拍)
 * b0=(I<0), b1=(Q<0) —— 与黄金模型 demod_qpsk 一致
 * (16QAM扩展: 电平±1/±3硬判, 阈值±10330, 判据见黄金模型 demod_qam16)
 */
`timescale 1ns/1ps
`include "ofdm_params.vh"

module qam_demapper (
    input  wire        clk, resetn,
    input  wire        s_axis_tvalid,
    input  wire [31:0] s_axis_tdata,
    output reg         m_axis_tvalid,
    input  wire        m_axis_tready,
    output reg [1:0]   m_axis_tdata
);
    assign m_axis_tvalid = s_axis_tvalid;

    always @(*) begin                     // 硬判是纯组合逻辑
        m_axis_tdata = {s_axis_tdata[31], s_axis_tdata[15]};  // {Q符号, I符号}
    end
endmodule
