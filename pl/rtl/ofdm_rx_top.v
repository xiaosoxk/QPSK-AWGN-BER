/**
 * ofdm_rx_top.v — RX链路顶层: 去CP → FFT → LS信道估计+均衡 → 硬判
 * 输入: 信道FIR输出(+噪声) 80采样/符号; 输出: 硬判比特流 → PS统计BER
 */
`timescale 1ns/1ps
`include "ofdm_params.vh"

module ofdm_rx_top (
    input  wire        clk, resetn,
    input  wire        rx_en,
    input  wire        pilot_pol,           // 导频极性(帧计数LSB, PS同步)
    input  wire        eq_enable,           // 均衡开关(对照实验)
    // 时域采样输入(来自信道FIR/ADC)
    input  wire        s_axis_tvalid,
    input  wire [31:0] s_axis_tdata,
    // 硬判比特输出(2bit/拍)
    output wire        m_axis_tvalid,
    output wire [1:0]  m_axis_tdata
);
    // 去CP → FFT
    wire rm_valid; wire [31:0] rm_data;
    cp_remove u_rm (
        .clk(clk), .resetn(resetn),
        .s_axis_tvalid(s_axis_tvalid), .s_axis_tdata(s_axis_tdata),
        .m_axis_tvalid(rm_valid), .m_axis_tready(1'b1),
        .m_axis_tdata(rm_data));

    wire fft_valid; wire [31:0] fft_data; wire fft_sof;
    fft_ifft_wrap #(.INVERSE(0)) u_fft (
        .clk(clk), .resetn(resetn),
        .s_axis_tvalid(rm_valid), .s_axis_tdata(rm_data),
        .m_axis_tvalid(fft_valid), .m_axis_tdata(fft_data),
        .event_frame_start(fft_sof));

    // LS估计 + 均衡
    wire eq_valid; wire [31:0] eq_data;
    chan_est_eq u_est (
        .clk(clk), .resetn(resetn),
        .s_axis_tvalid(fft_valid & rx_en), .s_axis_tdata(fft_data),
        .pilot_pol(pilot_pol),
        .m_axis_tvalid(eq_valid), .m_axis_tready(1'b1),
        .m_axis_tdata(eq_data));

    // 硬判
    qam_demapper u_demap (
        .clk(clk), .resetn(resetn),
        .s_axis_tvalid(eq_valid & eq_enable), .s_axis_tdata(eq_data),
        .m_axis_tvalid(m_axis_tvalid), .m_axis_tready(1'b1),
        .m_axis_tdata(m_axis_tdata));
endmodule
