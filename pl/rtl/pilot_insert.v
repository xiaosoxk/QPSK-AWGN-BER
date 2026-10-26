/**
 * pilot_insert.v — 48数据符号流 → 64bin完整频域符号
 * bin 0/27..37 → 0(保护), 导频bin → ±(1+j)/√2·2^14(极性按符号翻转), 其余 → 数据
 * 每符号计数 bin 0..63; tuser 标记符号边界
 */
`timescale 1ns/1ps
`include "ofdm_params.vh"

module pilot_insert (
    input  wire        clk, resetn,
    input  wire        s_axis_tvalid,       // 数据符号流(48/符号)
    input  wire [31:0] s_axis_tdata,
    output reg         m_axis_tvalid,       // 64bin频域符号流
    input  wire        m_axis_tready,
    output reg [31:0]  m_axis_tdata,
    output reg         m_axis_tuser         // 符号起始(bin0)标记
);
    localparam signed [15:0] P = 16'sd11585;   // (1+j)/√2 各分量 = 11585
    reg [6:0] bin;                             // 0..63
    reg       pol;                             // 导频极性(按符号翻转)
    reg       data_r;                          // 本bin是否数据

    wire [15:0] pilot_i = pol ? -P : P;

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            bin <= 0; m_axis_tvalid <= 0; pol <= 0; data_r <= 0;
        end else if (m_axis_tready || !m_axis_tvalid) begin
            m_axis_tvalid <= 1'b1;
            m_axis_tuser  <= (bin == 0);
            if (bin == 0)
                pol <= ~pol;                   // 每符号翻转导频极性
            if (is_data_bin(bin)) begin
                // 数据bin: 从输入流取(输入在数据bin节拍提供)
                m_axis_tdata <= s_axis_tvalid ? s_axis_tdata : 32'b0;
                data_r <= 1'b1;
            end else if (is_pilot_bin(bin)) begin
                m_axis_tdata <= (bin == `PILOT0 || bin == `PILOT1)
                              ? {pilot_i, pilot_i}      // +7,+21: +(1+j)
                              : {pilot_i, ~pilot_i + 1'b1}; // -7,-21: -(1+j)
                data_r <= 1'b0;
            end else begin
                m_axis_tdata <= 32'b0;         // DC/保护置零
                data_r <= 1'b0;
            end
            bin <= (bin == 63) ? 0 : bin + 1;
        end
    end

    // 数据bin时才接受输入数据(上游按USED表发48个/符号)
    wire unused_ok = data_r;
endmodule
