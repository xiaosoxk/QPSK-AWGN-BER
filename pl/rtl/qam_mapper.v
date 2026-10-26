/**
 * qam_mapper.v — QPSK 格雷映射 (AXI-Stream: 2bit/拍 → 复符号/拍, Q1.14)
 * 映射: (b0,b1) -> I=±1/√2·2^14=±11585, Q=±11585 (b=1→负)
 * 16QAM 扩展: 同结构, 电平±5165/±15497, 输入改4bit(见黄金模型gray_qam16)
 */
`timescale 1ns/1ps
`include "ofdm_params.vh"

module qam_mapper (
    input  wire        clk, resetn,
    input  wire        s_axis_tvalid,
    output wire        s_axis_tready,
    input  wire [1:0]  s_axis_tdata,
    output reg         m_axis_tvalid,
    input  wire        m_axis_tready,
    output reg [31:0]  m_axis_tdata
);
    localparam signed [15:0] QPSK_A = 16'sd11585;   // 1/√2 × 2^14

    assign s_axis_tready = m_axis_tready || !m_axis_tvalid;

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            m_axis_tvalid <= 1'b0;
            m_axis_tdata  <= 32'b0;
        end else if (s_axis_tvalid && s_axis_tready) begin
            m_axis_tvalid <= 1'b1;
            m_axis_tdata[15:0]  <= s_axis_tdata[0] ? -QPSK_A : QPSK_A;
            m_axis_tdata[31:16] <= s_axis_tdata[1] ? -QPSK_A : QPSK_A;
        end else if (m_axis_tready) begin
            m_axis_tvalid <= 1'b0;                 // 输出被取走且无新输入
        end
    end
endmodule
