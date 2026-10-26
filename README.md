# 基于ZYNQ的OFDM宽带通信基带系统（WiFi/4G底层核心）

PL(FPGA)与PS(Linux)软硬件协同的OFDM基带验证平台，对应《通信原理》核心内容：OFDM调制解调、循环前缀、导频与LS信道估计、多径信道与误码率测试。

## 系统架构
```
PS(Linux, ARM)                     PL(FPGA)
┌────────────────┐   AXI-Lite    ┌─────────────────────────────┐
│ BER统计+TCP服务 │◄─────────────►│ TX: QAM映射→导频→IFFT→加CP   │
│ 噪声方差控制    │               │      ↓                      │
│ 信道系数配置    │               │   3径FIR信道模拟(+噪声)       │
└────────────────┘               │      ↓                      │
                                 │ RX: 去CP→FFT→LS估计→均衡→硬判 │
       PC ◄──TCP :9000───────────┴─────────────────────────────┘
       ber_plot.py 绘制BER曲线
```

## 目录
```
golden/    Python黄金模型(浮点参考): ofdm_golden.py + test_golden.py(已验证)
           + gen_vectors.py(Verilog位精确比对向量)
pl/rtl/    Verilog: qam_mapper/demapper, pilot_insert, cp_insert/remove,
           chan_fir(多径模拟), noise_gen, chan_est_eq(LS+插值+均衡),
           fft_ifft_wrap(Xilinx FFT IP封装), ofdm_tx/rx_top
pl/tb/     tb_ofdm_chain.v(黄金向量位精确比对)
ps/        ber_server.c(Linux: BER统计+TCP上报)
pc/        ber_plot.py(BER曲线绘制)
```

## 已验证内容
- **Python黄金模型**(本机已跑通): QPSK AWGN BER 单调下降(0.22→6.8e-6@14dB)；
  3径多径+LS均衡 BER 接近AWGN(CP+均衡有效)；不均衡对照恶化6倍(证明信道估计价值)；
  16QAM 曲线正常。见 golden/ber_result.csv + ber_curves.png
- **黄金向量**: 平坦信道3帧2880位，供 tb_ofdm_chain.v 位精确比对

## 搭建步骤(见方案手册详细版)
1. Python: `python test_golden.py`(先验证算法) → `python gen_vectors.py`
2. Vivado 2022+: 建ZYNQ工程(PYNQ-Z2)，加 pl/rtl 全部文件，例化
   Xilinx FFT IP(64点/流水线/16位/缩放2^-6) 与 Divider IP(均衡除法)，
   AXI-GPIO/BRAM 连PS，按 README 寄存器表接线
3. 仿真: tb_ofdm_chain.v 行为级仿真 → error_count==0 即位精确PASS
4. Linux: PYNQ镜像启动，交叉编译 ps/ → ber_server，PC运行 pc/ber_plot.py
5. SNR扫描: PS逐点设噪声方差 → PC收集 → BER曲线 → 对比理论

## IP依赖
- Xilinx FFT (xfft_0): 64点/流水线/16位/缩放/自然序 (rtl/fft_ifft_wrap.v 注释)
- Xilinx Divider Generator (div_re/div_im): 32/18位 (chan_est_eq.v 均衡除法)

## 硬件平台
PYNQ-Z2 (ZYNQ Z7020)。仅用PL+千兆网口+UART，无需AD/DA(全数字闭环：
信道用FPGA内FIR模拟；接真实射频前端为升级方向)。
