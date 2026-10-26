/**
 * fft_ifft_wrap.v — Xilinx FFT IP 封装（64点, 供 TX 用 IFFT / RX 用 FFT）
 *
 * Vivado IP 配置(FFT IP Catalog → Xilinx FFT):
 *   Channels: 1 | Transform Length: 64 | Architecture: Pipelined Streaming I/O
 *   Input Data Width: 16 | Phase Factor Width: 16
 *   Scaling Option: Scaled (固定缩放, 6级各右移1位 = 2^-6, 见 PG109)
 *   Output Ordering: Natural Order | Round Mode: Convergent Rounding
 *   AXI4-Stream 接口: 勾选 (tuser 可选)
 *
 * IFFT 用法: 同一IP, aclk/en 配置为 Inverse FFT(经 s_axis_config_tdata 的 FWD/INV 位,
 *   该位映射在 config tdata 的 bit0 —— 详见 PG109 "Transform Configuration")
 * 缩放说明: IFFT 输出 = 输入和的量级, 64点固定缩放 2^-6 后幅度回到输入量级(Q1.14)
 */
`timescale 1ns/1ps
`include "ofdm_params.vh"

module fft_ifft_wrap #(
    parameter INVERSE = 0               // 0=FFT(RX) 1=IFFT(TX)
)(
    input  wire        clk, resetn,
    input  wire        s_axis_tvalid,    // 频域/时域输入(自然顺序)
    input  wire [31:0] s_axis_tdata,     // {imag[15:0], real[15:0]}
    output wire        m_axis_tvalid,
    output wire [31:0] m_axis_tdata,
    output wire        event_frame_start
);
    // Xilinx FFT IP 实例名: u_fft (IP名 xfft_0, 配置见上)
    wire ip_s_tready, ip_m_tvalid;
    wire [31:0] ip_m_tdata;
    wire [15:0] dummy_xk_index;

    xfft_0 u_fft (
        .aclk               (clk),
        .aresetn            (resetn),
        .s_axis_config_tvalid (1'b1),
        .s_axis_config_tdata  ({15'b0, INVERSE[0]}),   // bit0: 0=FFT 1=IFFT
        .s_axis_config_tready (/* 可接LED */),
        .s_axis_data_tvalid (s_axis_tvalid),
        .s_axis_data_tready (ip_s_tready),
        .s_axis_data_tdata  (s_axis_tdata),
        .s_axis_data_last   (1'b0),
        .m_axis_data_tvalid (ip_m_tvalid),
        .m_axis_data_tdata  (m_axis_tdata_ip),
        .m_axis_data_tuser  (dummy_xk_index),
        .event_frame_start  (event_frame_start)
    );
    wire [31:0] m_axis_tdata_ip;

    // 直通映射(输出自然顺序); 上游无反压时丢样本不可接受,
    // Pipelined Streaming IP 自带内部缓冲, tready 由外部保证消费速率≥输入速率
    assign m_axis_tvalid = ip_m_tvalid;
    assign m_axis_tdata  = m_axis_tdata_ip;
endmodule
