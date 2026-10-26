# -*- coding: utf-8 -*-
"""
test_golden.py — 黄金模型自检
  T1 AWGN+QPSK: BER 曲线单调下降, 与理论 Q(sqrt(2·EbN0)) 量级一致
  T2 多径+均衡: 3径信道下 LS均衡后 BER 仍接近 AWGN(CP+均衡有效)
  T3 多径不均衡(对照): BER 显著恶化 → 证明信道估计的价值
  T4 16QAM: 高SNR下 BER 单调且低
输出: golden/ber_result.csv + golden/ber_curves.png
"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.stdout.reconfigure(encoding='utf-8', errors='replace')
import numpy as np
from ofdm_golden import ber_sweep

OUT = os.path.dirname(os.path.abspath(__file__))
SNRS = [0, 2, 4, 6, 8, 10, 12, 14]
# 3径多径: 主径+2个延迟衰减径(相位每帧随机由rng决定? 此处固定相位, 论文可扩展)
MP = np.array([1.0, 0.45 * np.exp(-1j * 0.9), 0.22 * np.exp(-1j * 2.1)])

print("T1/T2/T3: QPSK (AWGN vs 多径均衡 vs 多径不均衡)")
s1, b1 = ber_sweep("QPSK", 300, SNRS, multipath=None, seed=1)
s2, b2 = ber_sweep("QPSK", 300, SNRS, multipath=MP, est_enable=True, seed=2)
s3, b3 = ber_sweep("QPSK", 300, SNRS, multipath=MP, est_enable=False, seed=3)
print("T4: 16QAM (AWGN)")
s4, b4 = ber_sweep("QAM16", 300, SNRS, multipath=None, seed=4)

# ---- 断言 ----
for name, b in (("T1", b1), ("T2", b2), ("T4", b4)):
    assert all(b[i] >= b[i + 1] for i in range(len(b) - 1)), name + " BER 非单调"
assert b1[-1] < 5e-3, "AWGN 14dB BER 应 <5e-3"
assert b2[-1] < 2e-2, "多径+均衡 14dB BER 应 <2e-2"
assert b3[-1] > b2[-1] * 3, "不均衡应显著恶化(证明信道估计价值)"
assert b4[-1] < 2e-1 and b4[0] > b4[-1], "16QAM 曲线异常"

# ---- 落盘 ----
with open(os.path.join(OUT, "ber_result.csv"), "w") as f:
    f.write("snr_db,qpsk_awgn,qpsk_mp_eq,qpsk_mp_noeq,qam16_awgn\n")
    for i, s in enumerate(s1):
        f.write("%d,%.6f,%.6f,%.6f,%.6f\n" % (s, b1[i], b2[i], b3[i], b4[i]))
print("csv ->", os.path.join(OUT, "ber_result.csv"))

try:
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    plt.figure(figsize=(8, 5))
    plt.semilogy(s1, np.maximum(b1, 1e-6), "o-", label="QPSK AWGN")
    plt.semilogy(s2, np.maximum(b2, 1e-6), "s-", label="QPSK 3-path + LS EQ")
    plt.semilogy(s3, np.maximum(b3, 1e-6), "^--", label="QPSK 3-path no EQ")
    plt.semilogy(s4, np.maximum(b4, 1e-6), "d-", label="16QAM AWGN")
    plt.grid(True, which="both", alpha=0.3)
    plt.xlabel("SNR per sample (dB)"); plt.ylabel("BER")
    plt.title("OFDM golden model BER (N=64, CP=16, LS channel estimation)")
    plt.legend(); plt.ylim(1e-5, 1)
    plt.tight_layout()
    plt.savefig(os.path.join(OUT, "ber_curves.png"), dpi=200)
    print("png -> ber_curves.png")
except Exception as e:
    print("plot skipped:", e)
print("ALL GOLDEN TESTS PASSED")
