/**
 * ofdm_tx_top.v — TX链路顶层: QAM映射 → 导频插入 → IFFT → 加CP
 * AXI-Stream: 输入比特流(PS经BRAM/GPIO写入), 输出时域采样 → 信道FIR
 * 帧结构: 10符号×80采样, tuser标记帧/符号起始
 */
`timescale 1ns/1ps
`include "ofdm_params.vh"

module ofdm_tx_top (
    input  wire        clk, resetn,
    input  wire        tx_en,               // PS使能
    // 比特输入流(来自PS写TX BRAM, 简单BRAM读接口)
    input  wire        s_axis_tvalid,       // 2bit/拍
    input  wire [1:0]  s_axis_tdata,
    output wire        s_axis_tready,
    // 时域采样输出(送信道FIR/DAC)
    output wire        m_axis_tvalid,
    output wire [31:0] m_axis_tdata,
    output wire        m_axis_tuser         // 帧起始标记
);
    // mapper → pilot_insert
    wire map_valid, map_ready; wire [31:0] map_sym;
    qam_mapper u_map (
        .clk(clk), .resetn(resetn),
        .s_axis_tvalid(s_axis_tvalid), .s_axis_tready(s_axis_tready),
        .s_axis_tdata(s_axis_tdata),
        .m_axis_tvalid(map_valid), .m_axis_tready(map_ready),
        .m_axis_tdata(map_sym));

    // pilot_insert → ifft
    wire pi_valid; wire pi_ready; wire [31:0] pi_data; wire pi_sof;
    pilot_insert u_pilot (
        .clk(clk), .resetn(resetn),
        .s_axis_tvalid(map_valid), .s_axis_tdata(map_sym),
        .m_axis_tvalid(pi_valid), .m_axis_tready(pi_ready),
        .m_axis_tdata(pi_data), .m_axis_tuser(pi_sof));

    // IFFT
    wire ifft_valid; wire [31:0] ifft_data; wire ifft_sof;
    fft_ifft_wrap #(.INVERSE(1)) u_ifft (
        .clk(clk), .resetn(resetn),
        .s_axis_tvalid(pi_valid & pi_ready), .s_axis_tdata(pi_data),
        .m_axis_tvalid(ifft_valid), .m_axis_tdata(ifft_data),
        .event_frame_start(ifft_sof));

    // 加CP
    cp_insert u_cp (
        .clk(clk), .resetn(resetn),
        .s_axis_tvalid(ifft_valid), .s_axis_tdata(ifft_data),
        .m_axis_tvalid(m_axis_tvalid), .m_axis_tready(1'b1),
        .m_axis_tdata(m_axis_tdata));

    assign m_axis_tuser = ifft_sof;          // 帧起始(简化: 符号起始)
endmodule
