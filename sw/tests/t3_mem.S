    # 测试 3：访存。sw/sh/sb 写到不同的字节偏移，再用 lw/lh/lhu/lb/lbu 读回
    # 测试平台检查：结束时 a0 = 0（所有比较都对）；另外直接检查存储器里 buf 的三个字（地址固定为 0x80001000）
    .section .text.init
    .globl _start
_start:
    li    a0, 0
    la    s0, buf             # s0 = buf 的地址（4 字节对齐）

    li    t0, 0x87654321
    sw    t0, 0(s0)           # buf[0..3] = 21 43 65 87（小端）

    lw    t1, 0(s0)
    bne   t1, t0, fail        # lw 读回原值

    lb    t1, 3(s0)           # 字节 3 = 0x87，符号扩展 = 0xffffff87
    li    t2, 0xffffff87
    bne   t1, t2, fail
    lbu   t1, 3(s0)           # 零扩展 = 0x87
    li    t2, 0x87
    bne   t1, t2, fail
    lb    t1, 1(s0)           # 字节 1 = 0x43，正数
    li    t2, 0x43
    bne   t1, t2, fail

    lh    t1, 2(s0)           # 半字 [3:2] = 0x8765，符号扩展
    li    t2, 0xffff8765
    bne   t1, t2, fail
    lhu   t1, 2(s0)
    li    t2, 0x8765
    bne   t1, t2, fail
    lh    t1, 0(s0)           # 半字 [1:0] = 0x4321
    li    t2, 0x4321
    bne   t1, t2, fail

    li    t0, 0xaabbccdd
    sb    t0, 1(s0)           # 只改字节 1：buf[0..3] = 21 dd 65 87
    sh    t0, 6(s0)           # 只改字节 6、7：buf[4..7] = 00 00 dd cc
    li    t0, 0x11223344
    sw    t0, 8(s0)           # buf[8..11] = 44 33 22 11
    sb    t0, 8(s0)           # 字节 8 再写一次 0x44（值不变，测“只写一个字节”）

    lw    t1, 0(s0)
    li    t2, 0x8765dd21
    bne   t1, t2, fail
    lw    t1, 4(s0)
    li    t2, 0xccdd0000
    bne   t1, t2, fail
    lw    t1, 8(s0)
    li    t2, 0x11223344
    bne   t1, t2, fail
    ebreak

fail:
    li    a0, 0xbad
    ebreak

    # buf 放在固定地址 0x80001000，测试平台据此直接检查存储器（链接时用 -Wl,--section-start）
    .section .buf, "aw"
    .balign 4
buf:
    .word 0, 0, 0
