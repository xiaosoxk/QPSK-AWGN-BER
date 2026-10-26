# PS Linux 交叉编译 Makefile
# 工具链: PYNQ 镜像自带或 apt install gcc-arm-linux-gnueabihf
# 也可直接在 PYNQ 板上 gcc 编译(镜像带gcc)
CC ?= arm-linux-gnueabihf-gcc
CFLAGS = -O2 -Wall

all: ber_server

ber_server: src/ber_server.c
	$(CC) $(CFLAGS) -o $@ $<

# 直接在板上编译: scp 本目录到板子后 make CC=gcc
clean:
	rm -f ber_server
