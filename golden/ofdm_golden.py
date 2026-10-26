# -*- coding: utf-8 -*-
"""
ofdm_golden.py — OFDM 基带黄金模型（浮点参考实现, Verilog 的对照基准）

参数对齐 802.11a 缩水版（WiFi 底层核心, 论文/答辩可直接引用）:
  N_FFT=64, CP=16, 每帧 10 个 OFDM 符号
  子载波: 48 数据 + 4 导频(comb, ±7/±21) + DC与边带置零 = 64
  调制: QPSK / 16QAM (格雷映射), LS信道估计 + 线性插值 + 单抽头均衡
  信道: AWGN / 3径多径(每帧随机相位), CP=16 ≥ 时延扩展 → ISG(符号间干扰)被CP吸收

链路: bits → QAM映射 → 导频插入 → IFFT → 加CP → 多径信道 → AWGN
      → 去CP → FFT → LS信道估计(导频) → 插值/均衡 → 硬判 → BER
"""
import numpy as np

# ---------------- 参数 ----------------
N_FFT   = 64
CP_LEN  = 16
N_SYM   = 10                      # 每帧OFDM符号数
PILOTS  = np.array([7, 21, 43, 57])          # ±7, ±21 (comb)
PILOT_VAL = (1 + 1j) / np.sqrt(2)            # BPSK导频
# 数据子载波: 符号频率 ±1..±26 (bin 1..26 与 38..63, 共52个), 导频在其中4个
# 置零: bin 0(DC) 与保护边带(±27..±31, 即 bin 27..31 与 32..37) —— 802.11a结构
USED    = np.array([k for k in range(64) if k != 0 and k not in PILOTS
                    and (1 <= k <= 26 or 38 <= k <= 63)])
N_DATA  = len(USED)               # 48
N_BITS_SYM = {"QPSK": 2, "QAM16": 4}
SIGNED  = np.array([(k if k < 32 else k - 64) for k in range(N_FFT)])


def gray_qpsk(bits):
    """QPSK格雷映射: (b0,b1) -> (±1±j)/√2"""
    b = bits.reshape(-1, 2).astype(float)
    return ((1 - 2 * b[:, 0]) + 1j * (1 - 2 * b[:, 1])) / np.sqrt(2)


def gray_qam16(bits):
    """16QAM格雷映射: 每4bit -> 幅度电平(±1,±3)/√10
    电平映射: +3=(0,0) +1=(0,1) -1=(1,1) -3=(1,0) (格雷: 相邻差1bit)"""
    b = bits.reshape(-1, 4).astype(float)
    lvl = (1 - 2 * b[:, 0]) * (2 - (1 - 2 * b[:, 1]))   # I路
    qlv = (1 - 2 * b[:, 2]) * (2 - (1 - 2 * b[:, 3]))   # Q路
    return (lvl + 1j * qlv) / np.sqrt(10)


def demod_qpsk(sym):
    return np.stack([(sym.real < 0).astype(np.uint8),
                     (sym.imag < 0).astype(np.uint8)], axis=-1).reshape(-1)


def demod_qam16(sym):
    """硬判(与映射表互逆): p0=(符号位), p1=(|幅度|>2)
    映射表: +1=(0,0) +3=(0,1) -1=(1,0) -3=(1,1)"""
    r = sym.real * np.sqrt(10)
    i = sym.imag * np.sqrt(10)
    rb = np.stack([(r < 0).astype(np.uint8),
                   (np.abs(r) > 2).astype(np.uint8)], axis=-1)
    ib = np.stack([(i < 0).astype(np.uint8),
                   (np.abs(i) > 2).astype(np.uint8)], axis=-1)
    return np.concatenate([rb, ib], axis=-1).reshape(-1)


def make_frame(bits, mode="QPSK"):
    """比特 -> 一帧时域采样(10个OFDM符号, 各含CP)
    返回 (tx_time, 48x10数据符号, 原始比特)"""
    nb = N_BITS_SYM[mode]
    assert len(bits) == N_DATA * N_SYM * nb
    q = gray_qpsk(bits) if mode == "QPSK" else gray_qam16(bits)
    out_time = []
    for s in range(N_SYM):
        X = np.zeros(N_FFT, dtype=complex)
        X[USED] = q[s * N_DATA:(s + 1) * N_DATA]
        X[PILOTS] = PILOT_VAL * (1 if s % 2 == 0 else -1)   # 导频极性翻转
        x = np.fft.ifft(X) * np.sqrt(N_FFT)                 # 功率归一
        out_time.append(np.concatenate([x[-CP_LEN:], x]))   # 加CP
    return np.concatenate(out_time), q, bits


def channel(tx, snr_db, multipath=None, rng=None):
    """多径FIR + AWGN。snr_db 为每采样信噪比(含CP开销)"""
    rng = rng or np.random.default_rng()
    y = tx
    if multipath is not None:
        y = np.convolve(tx, multipath)[: len(tx)]
    p_sig = np.mean(np.abs(y) ** 2)
    n0 = p_sig / (10 ** (snr_db / 10))
    n = np.sqrt(n0 / 2) * (rng.standard_normal(len(y)) +
                           1j * rng.standard_normal(len(y)))
    return y + n


def rx_chain(rx_time, mode="QPSK", est_enable=True):
    """去CP → FFT → LS估计(导频) → 线性插值 → 单抽头均衡 → 硬判"""
    sym_len = N_FFT + CP_LEN
    n_sym = len(rx_time) // sym_len
    out_bits = []
    for s in range(n_sym):
        seg = rx_time[s * sym_len:(s + 1) * sym_len]
        Y = np.fft.fft(seg[CP_LEN:]) / np.sqrt(N_FFT)
        # LS信道估计: 导频处 H = Y / Xp (导频极性已知)
        Hp = Y[PILOTS] / (PILOT_VAL * (1 if s % 2 == 0 else -1))
        # 导频按符号频率排序后线性插值到全部子载波
        order = np.argsort(SIGNED[PILOTS])
        p_bins = PILOTS[order]
        H_full = np.interp(SIGNED, SIGNED[p_bins], Hp[order]).astype(complex)
        Eq = Y[USED] / (H_full[USED] if est_enable else np.ones(N_DATA))
        out_bits.append(demod_qpsk(Eq) if mode == "QPSK" else demod_qam16(Eq))
    return np.concatenate(out_bits)


def ber_sweep(mode="QPSK", n_frames=200, snr_list=None, multipath=None,
              est_enable=True, seed=0, verbose=True):
    """扫SNR统计BER, 返回 (snr_list, ber_list)"""
    snr_list = snr_list or list(range(0, 21, 2))
    rng = np.random.default_rng(seed)
    nb = N_BITS_SYM[mode]
    res = []
    for snr in snr_list:
        err = tot = 0
        for _ in range(n_frames):
            tx_bits = rng.integers(0, 2, N_DATA * N_SYM * nb).astype(np.uint8)
            tx, _, _ = make_frame(tx_bits, mode)
            rx = channel(tx, snr, multipath, rng)
            rx_bits = rx_chain(rx, mode, est_enable)
            err += int(np.sum(rx_bits != tx_bits))
            tot += len(tx_bits)
        res.append(err / tot)
        if verbose:
            print("  SNR %5.1f dB  BER %.3e" % (snr, res[-1]))
    return snr_list, res
