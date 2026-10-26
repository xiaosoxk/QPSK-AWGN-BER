/**
 * ber_server.c — PS(Linux)端: BER统计 + TCP上报
 * 平台: PYNQ-Z2 Linux (Ubuntu/PYNQ image), 交叉编译 arm-linux-gnueabihf-gcc
 *
 * 数据通路: PL寄存器(/dev/uio0 映射)读取 帧计数/误比特计数 → 周期计算BER
 *          → TCP :9000 逐行JSON发PC: {"snr_db":8.0,"frames":1000,"ber":0.0123}
 * SNR扫描: PS写噪声方差寄存器(var_scale), PC端发 "SET <snr> <var>" 命令控制
 *
 * PL寄存器映射(AXI-GPIO, 基址由设备树, 默认0x40000000):
 *   +0x00: rw  CTRL   (bit0 rx_en, bit1 eq_enable)
 *   +0x04: rw  VAR    (noise_gen var_scale, Q1.14)
 *   +0x08: rw  TAP_R0/I0..TAP2 (3径系数, 6×32bit, +0x0C..0x20)
 *   +0x40: ro  BIT_TOTAL
 *   +0x44: ro  BIT_ERROR
 *   +0x48: ro  FRAME_CNT
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/socket.h>
#include <netinet/in.h>

#define UIO_DEV   "/dev/uio0"
#define REG_CTRL  0x00
#define REG_VAR   0x04
#define REG_TAPR0 0x0C
#define REG_BITT  0x40
#define REG_BERR  0x44
#define REG_FRAME 0x48

static volatile unsigned *regs;

static unsigned reg_rd(unsigned off) { return regs[off / 4]; }
static void reg_wr(unsigned off, unsigned v) { regs[off / 4] = v; }

int main(int argc, char **argv)
{
    int uio = open(UIO_DEV, O_RDWR);
    if (uio < 0) { perror("uio open"); return 1; }
    regs = mmap(NULL, 4096, PROT_READ | PROT_WRITE, MAP_SHARED, uio, 0);
    if (regs == MAP_FAILED) { perror("mmap"); return 1; }

    /* 默认信道系数: 平坦[1,0,0] → 多径时改写 TAP 寄存器(Q1.14) */
    reg_wr(REG_TAPR0, 0x4000);           /* h0 = 1.0 (Q1.14) */

    int srv = socket(AF_INET, SOCK_STREAM, 0);
    int yes = 1;
    setsockopt(srv, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof yes);
    struct sockaddr_in a = {0};
    a.sin_family = AF_INET;
    a.sin_addr.s_addr = INADDR_ANY;
    a.sin_port = htons(9000);
    if (bind(srv, (struct sockaddr *)&a, sizeof a) < 0) { perror("bind"); return 1; }
    listen(srv, 1);
    printf("BER server ready on :9000\n");

    unsigned prev_bits = 0, prev_err = 0;
    int cli = accept(srv, NULL, NULL);
    printf("PC connected\n");

    char line[128];
    unsigned prev_frame = 0;
    while (1) {
        /* 非阻塞读PC命令: "SET <var_scale>" / "EN 1" */
        int n = recv(cli, line, sizeof line - 1, MSG_DONTWAIT);
        if (n > 0) {
            line[n] = 0;
            if (strncmp(line, "SET ", 4) == 0) {
                unsigned var = strtoul(line + 4, NULL, 0);
                reg_wr(REG_VAR, var);
            } else if (strncmp(line, "EN ", 3) == 0) {
                reg_wr(REG_CTRL, strtoul(line + 3, NULL, 0));
            }
        }
        /* 读PL计数器 → 计算本周期BER */
        unsigned bt = reg_rd(REG_BITT);
        unsigned be = reg_rd(REG_BERR);
        unsigned fr = reg_rd(REG_FRAME);
        unsigned d_bits = bt - prev_bits, d_err = be - prev_err, d_fr = fr - prev_frame;
        double ber = d_bits ? (double)d_err / d_bits : 0.0;
        prev_bits = bt; prev_err = be; prev_frame = fr;

        /* JSON行发给PC */
        int len = snprintf(line, sizeof line,
            "{\"frames\":%u,\"bits\":%u,\"err\":%u,\"ber\":%.6f}\n",
            d_fr, d_bits, d_err, ber);
        if (send(cli, line, len, MSG_DONTWAIT) < 0) {
            cli = accept(srv, NULL, NULL);   /* PC断开: 等重连 */
            printf("PC reconnected\n");
        }
        usleep(100000);                       /* 10Hz 上报 */
    }
}
