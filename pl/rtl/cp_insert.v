/**
 * cp_insert.v — IFFT输出64点 → 加循环前缀输出80点
 * 双口BRAM缓存一个符号(64点), 写满后先重读末16点(=CP)再顺序读64点
 */
`timescale 1ns/1ps
`include "ofdm_params.vh"

module cp_insert (
    input  wire        clk, resetn,
    input  wire        s_axis_tvalid,       // IFFT输出, 64点/符号
    input  wire [31:0] s_axis_tdata,
    output reg         m_axis_tvalid,       // 80点/符号(16CP+64数据)
    input  wire        m_axis_tready,
    output reg [31:0]  m_axis_tdata
);
    (* ram_style = "block" *) reg [31:0] mem [0:`N_FFT-1];
    reg [6:0] wcnt;                            // 写计数 0..63
    reg [7:0] rcnt;                            // 读计数 0..79
    reg       writing;

    wire [6:0] rd_addr = (rcnt < `CP_LEN) ? (rcnt + `N_FFT - `CP_LEN)  // CP=末16点
                                         : (rcnt - `CP_LEN);           // 数据=0..63
    assign m_axis_tdata = mem[rd_addr];
    assign m_axis_tvalid = ~writing;

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            wcnt <= 0; rcnt <= 0; writing <= 1'b1;
        end else if (writing) begin
            if (s_axis_tvalid) begin
                mem[wcnt] <= s_axis_tdata;
                wcnt <= wcnt + 1;
                if (wcnt == `N_FFT - 1) begin
                    writing <= 1'b0;           // 写满64点 → 转读出
                    rcnt   <= 0;
                end
            end
        end else if (m_axis_tready) begin
            rcnt <= rcnt + 1;
            if (rcnt == `SYM_LEN - 1) begin
                writing <= 1'b1;               // 80点读毕 → 下一符号
                rcnt <= 0;
            end
        end
    end
endmodule
