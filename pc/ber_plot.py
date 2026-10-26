# -*- coding: utf-8 -*-
"""
ber_plot.py — PC端: 连接PS的TCP :9000, 接收BER数据, SNR扫描后绘制BER曲线
用法:
  1) PC运行本脚本 → 等待连接PS
  2) PS端(python/串口)逐点设置噪声方差并等待, 本脚本实时记录
  3) Ctrl+C 结束 → 输出 ber_sweep.csv + ber_sweep.png
命令(发给PS): SET <var> 写噪声方差; EN <01> 使能
"""
import sys, os, socket, json, time
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

HOST = sys.argv[1] if len(sys.argv) > 1 else "192.168.2.99"   # PYNQ 板IP
PORT = 9000

# SNR扫描表: (SNR标签, var_scale Q1.14) —— var 与 SNR 的对应关系需一次标定
SWEEP = [(0, 16384), (2, 13031), (4, 10343), (6, 8216), (8, 6527),
         (10, 5185), (12, 4120), (14, 3273)]

sock = socket.create_connection((HOST, PORT), timeout=10)
print("connected to", HOST)
results = []
buf = ""

def set_snr(label, var):
    sock.sendall(("SET %d\n" % var).encode())
    print("SET SNR=%s var=%d, collecting..." % (label, var))
    time.sleep(3.0)                        # 每点采集3秒

for label, var in SWEEP:
    set_snr(label, var)
    sock.settimeout(2.0)
    try:
        while True:                        # 清空积压
            buf += sock.recv(4096).decode()
    except socket.timeout:
        pass
    lines = buf.strip().split("\n")
    buf = lines[-1]
    recs = [json.loads(l) for l in lines[:-1] if l.startswith("{")]
    if recs:
        ber = sum(r["ber"] for r in recs) / len(recs)
        results.append((label, ber))
        print("  SNR %s dB -> BER %.5f" % (label, ber))

os.makedirs("out", exist_ok=True)
with open("out/ber_sweep.csv", "w") as f:
    f.write("snr_db,ber\n")
    for s, b in results:
        f.write("%s,%s\n" % (s, b))
plt.figure(figsize=(8, 5))
plt.semilogy([s for s, _ in results], [max(b, 1e-6) for _, b in results], "o-")
plt.grid(True, which="both", alpha=0.3)
plt.xlabel("SNR (dB)"); plt.ylabel("BER")
plt.title("ZYNQ OFDM measured BER (live from board)")
plt.tight_layout()
plt.savefig("out/ber_sweep.png", dpi=200)
print("saved out/ber_sweep.csv + out/ber_sweep.png")
