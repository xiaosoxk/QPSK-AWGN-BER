/**
 * cp_remove.v — 输入80点/符号 → 丢弃前16点(CP) → 输出64点
 * 计数器实现, 无需RAM(流式丢弃)
 */
`timescale 1ns/1ps
`include "ofdm_params.vh"

module cp_remove (
    input  wire        clk, resetn,
    input  wire        s_axis_tvalid,
    input  wire [31:0] s_axis_tdata,
    output reg         m_axis_tvalid,
    input  wire        m_axis_tready,
    output reg [31:0]  m_axis_tdata
);
    reg [7:0] cnt;                             // 0..79

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            cnt <= 0; m_axis_tvalid <= 0; m_axis_tdata <= 0;
        end else if (s_axis_tvalid && (m_axis_tready || !m_axis_tvalid)) begin
            cnt <= (cnt == `SYM_LEN - 1) ? 0 : cnt + 1;
            if (cnt >= `CP_LEN) begin          // 后64点 = 有效FFT窗口
                m_axis_tvalid <= 1'b1;
                m_axis_tdata  <= s_axis_tdata;
            end else begin
                m_axis_tvalid <= 1'b0;         // CP区间丢弃
            end
        end else if (m_axis_tready) begin
            m_axis_tvalid <= 1'b0;
        end
    end
endmodule
