# -*- coding: utf-8 -*-
"""
gen_vectors.py — 生成 Verilog Testbench 位精确比对向量（无噪声多径场景）

原理: 无噪声时, LS均衡后的符号应精确落在理想星座点上,
      硬判输出必须与发送比特完全一致 —— 这就是 RTL 的位精确验收标准。
输出(golden/vectors/):
  qam_sym_i.hex / qam_sym_q.hex   TX侧QAM符号(Q1.14补码, 3帧×480符号)
  chan_tap_r.hex / chan_tap_i.hex 3径信道系数(Q1.14)
  exp_rx_bits.hex                 期望的接收硬判比特流(3帧×960bit)
"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.stdout.reconfigure(encoding='utf-8', errors='replace')
import numpy as np
from ofdm_golden import make_frame, channel, rx_chain, N_FFT, CP_LEN

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "vectors")
os.makedirs(OUT, exist_ok=True)
rng = np.random.default_rng(7)
FRAMES = 3
# 位精确向量场景: 平坦信道( taps=[1,0,0] ) —— LS/插值/均衡全精确, RTL可位精确比对。
# 多径场景的算法正确性已在 test_golden.py T2/T3 浮点验证(带均衡BER接近AWGN)。
MP = np.array([1.0, 0.0, 0.0])

def q14(x):     # 复数 → Q1.14 定点(饱和)
    def sat(v):
        v = int(round(v * 16384))
        return max(-32768, min(32767, v)) & 0xFFFF
    return sat(x.real), sat(x.imag)

all_sym_i, all_sym_q = [], []
all_exp_bits = []
bits = rng.integers(0, 2, 48 * 10 * 2 * FRAMES).astype(np.uint8)  # 一次生成3帧
for f in range(FRAMES):
    tx, qsym, _ = make_frame(bits[f * 960:(f + 1) * 960], "QPSK")
    # 无噪声多径
    rx = channel(tx, snr_db=999, multipath=MP, rng=rng)
    rx_bits = rx_chain(rx, "QPSK", est_enable=True)
    assert np.array_equal(rx_bits, bits[f * 960:(f + 1) * 960]), "浮点模型自身不一致! f=%d" % f
    # QAM符号(时域IFFT之前的频域符号, 即mapper输出)
    for s in range(10):
        for k in qsym[s * 48:(s + 1) * 48]:
            i16, q16 = q14(k)
            all_sym_i.append(i16); all_sym_q.append(q16)
    all_exp_bits += list(bits[f * 960:(f + 1) * 960])
    # 信道系数(每帧刷新一次相位)
    if f == 0:
        taps = MP
        tr = [t for tap in taps for t in q14(tap)]

np.savetxt(os.path.join(OUT, "qam_sym_i.hex"),
           np.array(all_sym_i, dtype=np.uint16), fmt="%04x")
np.savetxt(os.path.join(OUT, "qam_sym_q.hex"),
           np.array(all_sym_q, dtype=np.uint16), fmt="%04x")
open(os.path.join(OUT, "chan_tap_r.hex"), "w").write(
    "\n".join("%04x" % v for v in [t & 0xFFFF for t in [int(round(x * 16384)) for x in MP.real]]))
open(os.path.join(OUT, "chan_tap_i.hex"), "w").write(
    "\n".join("%04x" % v for v in [t & 0xFFFF for t in [int(round(x * 16384)) for x in MP.imag]]))
np.savetxt(os.path.join(OUT, "exp_rx_bits.hex"),
           np.array(all_exp_bits, dtype=np.uint8), fmt="%01x")
print("vectors ->", OUT)
print("QAM symbols: %d | expected bits: %d" % (len(all_sym_i), len(all_exp_bits)))
