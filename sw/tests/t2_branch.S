    # 测试 2：分支和跳转。6 种分支各测“跳”和“不跳”，再测 jal、jalr、auipc
    # 每通过一项 a0 加 1，任何一处走错路都会跑进 fail（a0 = 0xbad）
    # 测试平台检查：结束时 a0 = 14（下面标了“第 1～14 项”）
    .section .text.init
    .globl _start
_start:
    li    a0, 0
    li    t0, 5
    li    t1, -3
    li    t2, 5

    beq   t0, t2, 1f          # 5 == 5：跳
    j     fail
1:  addi  a0, a0, 1           # 第 1 项
    beq   t0, t1, fail        # 5 == -3：不跳
    addi  a0, a0, 1           # 第 2 项

    bne   t0, t1, 2f          # 跳
    j     fail
2:  addi  a0, a0, 1           # 第 3 项

    blt   t1, t0, 3f          # -3 < 5（有符号）：跳
    j     fail
3:  addi  a0, a0, 1           # 第 4 项
    blt   t0, t1, fail        # 5 < -3：不跳
    addi  a0, a0, 1           # 第 5 项

    bge   t0, t2, 4f          # 5 >= 5：跳
    j     fail
4:  addi  a0, a0, 1           # 第 6 项

    bltu  t0, t1, 5f          # 5 < 0xfffffffd（无符号）：跳
    j     fail
5:  addi  a0, a0, 1           # 第 7 项
    bltu  t1, t0, fail        # 无符号下 -3 很大：不跳
    addi  a0, a0, 1           # 第 8 项

    bgeu  t1, t0, 6f          # 跳
    j     fail
6:  addi  a0, a0, 1           # 第 9 项

    jal   ra, func            # 调用：ra = 返回地址
    addi  a0, a0, 1           # 第 10 项：从 func 回来后执行

    auipc t3, 0               # t3 = 这条 auipc 自己的 PC
7:  addi  t3, t3, 24          # t3 = auipc 的 PC + 24 = 下面 jalr_target 的地址（中间隔 6 条指令）
    jalr  zero, 0(t3)         # 跳过下面三条 j fail
    j     fail
    j     fail
    j     fail
jalr_target:
    addi  a0, a0, 1           # 第 11 项：jalr 的目标

    la    t4, odd_target
    addi  t4, t4, 1           # 故意让地址变奇数，jalr 应该清掉最低位
    jalr  zero, 0(t4)
    j     fail
odd_target:
    addi  a0, a0, 1           # 第 12 项
    addi  a0, a0, 1           # 第 13 项
    ebreak

func:
    addi  a0, a0, 1           # 第 14 项
    ret                       # jalr zero, 0(ra)

fail:
    li    a0, 0xbad
    ebreak
