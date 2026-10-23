    # 测试 1：只有寄存器运算和立即数运算，没有跳转、没有访存
    # 把每一步的结果按固定的加减组合累加进 a0，任何一条算错，最后的 a0 都不会等于 42
    # 测试平台检查：结束时 a0 = 0x0000002a（42）
    .section .text.init
    .globl _start
_start:
    addi  t0, zero, 20        # t0 = 20
    addi  t1, zero, -7        # t1 = -7
    add   t2, t0, t1          # t2 = 13
    sub   t3, t0, t1          # t3 = 27
    slli  t4, t2, 2           # t4 = 52
    srai  t5, t1, 1           # t5 = -4（算术右移，补符号位）
    srli  t6, t1, 28          # t6 = 15（逻辑右移，补 0）
    slt   s0, t1, t0          # s0 = 1（-7 < 20）
    sltu  s1, t1, t0          # s1 = 0（0xfffffff9 > 20）
    xori  a2, t3, 0x0f        # a2 = 27 ^ 15 = 20
    andi  a3, t4, 0x30        # a3 = 52 & 48 = 48
    ori   a4, s0, 0x40        # a4 = 65
    lui   a5, 0x12345         # a5 = 0x12345000
    srli  a5, a5, 24          # a5 = 0x12 = 18
    # 42 = 13 + 27 + 52 + (-4) + 15 + 1 + 0 - 20 - 48 - 65 + 18 + 53
    add   a0, t2, t3          # 40
    add   a0, a0, t4          # 92
    add   a0, a0, t5          # 88
    add   a0, a0, t6          # 103
    add   a0, a0, s0          # 104
    add   a0, a0, s1          # 104
    sub   a0, a0, a2          # 84
    sub   a0, a0, a3          # 36
    sub   a0, a0, a4          # -29
    add   a0, a0, a5          # -11
    addi  a0, a0, 53          # 42
    ebreak
