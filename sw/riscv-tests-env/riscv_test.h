// mycore 的 riscv-tests 运行环境：替换官方 env/p/riscv_test.h
//
// 官方 p 环境在启动时要读写一串 CSR（mtvec、mstatus、mepc、mhartid……），
// 再用 mret 进入测试，结束时用 ecall 进陷阱、把结果写到 tohost。
// mycore 还没有 CSR 和异常机制，所以这里换成最小的约定：
//   - 从 _start 直接开始执行测试，不做任何特权初始化
//   - 通过：a0 = 0，然后 ebreak
//   - 失败：a0 = (测试号 << 1) | 1，然后 ebreak；测试号 = (a0 - 1) / 2
// 测试平台用 +expect_a0=0 判断 PASS，和 sw/tests/ 下的程序是同一套约定。
// 测试本身（isa/rv32ui/*.S）和测试宏（isa/macros/scalar/test_macros.h）不改，原样使用。
#ifndef _ENV_MYCORE_H
#define _ENV_MYCORE_H

// 测试文件开头写 RVTEST_RV32U（或 RV64U，rv32ui 会把它重定义成 RV32U），
// 它在官方环境里定义一个 init 宏做初始化。rv32ui 不需要初始化，留空。
#define RVTEST_RV64U .macro init; .endm
#define RVTEST_RV32U .macro init; .endm

// 当前测试号放在 gp（x3）里，测试宏 TEST_CASE 每一项开头都会 li gp, 编号
#define TESTNUM gp

#define RVTEST_CODE_BEGIN                                               \
        .section .text.init;                                            \
        .align  6;                                                      \
        .globl _start;                                                  \
_start:                                                                 \
        li TESTNUM, 0;

#define RVTEST_CODE_END                                                 \
        unimp

#define RVTEST_PASS                                                     \
        fence;                                                          \
        li TESTNUM, 1;                                                  \
        li a0, 0;                                                       \
        ebreak

// 和官方一样把测试号编码进 a0：低位 1 表示失败，高位是测试号
#define RVTEST_FAIL                                                     \
        fence;                                                          \
1:      beqz TESTNUM, 1b;                                               \
        sll TESTNUM, TESTNUM, 1;                                        \
        or TESTNUM, TESTNUM, 1;                                         \
        addi a0, TESTNUM, 0;                                            \
        ebreak

#define EXTRA_DATA

// 官方在这里放 tohost / fromhost；这个环境不用它们，只保留签名区的标号
#define RVTEST_DATA_BEGIN                                               \
        EXTRA_DATA                                                      \
        .align 4; .global begin_signature; begin_signature:

#define RVTEST_DATA_END .align 4; .global end_signature; end_signature:

#endif
