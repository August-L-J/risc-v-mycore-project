// 整核测试平台：加载程序 → 复位 → 每拍执行一条指令，直到 ebreak / 非法指令 / 超时
// 用法：Vsoc_top +prog=xxx.hex [+trace] [+max=N] [+expect_a0=HEX] [+expect_mem=ADDR:HEX]
//   +trace           每条指令打印一行：PC、机器码、写回的寄存器和值、存储器写
//   +max=N           最多跑 N 拍（默认 100000），防止死循环
//   +expect_a0=HEX   结束时检查 a0（x10）等于这个值
//   +expect_mem=A:V  结束时检查存储器字地址 A 的值等于 V（十六进制，可重复多次，最多 16 个）
//   +wave=FILE.fst   记录 FST 波形（只有 make core-wave 编译的版本支持），每拍两个时间点：clk 低、clk 高
// 结束原因和检查结果打印一行 “CORE: ... -> PASS/FAIL”，返回值 0 表示 PASS
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <memory>
#include <string>
#include <vector>
#include "Vsoc_top.h"
#include "Vsoc_top___024root.h"
#include "verilated.h"
#if VM_TRACE_FST
#include "verilated_fst_c.h"
#endif

static const char* kAbi[32] = {"zero", "ra", "sp", "gp", "tp", "t0", "t1", "t2", "s0", "s1", "a0",
                               "a1",   "a2", "a3", "a4", "a5", "a6", "a7", "s2", "s3", "s4", "s5",
                               "s6",   "s7", "s8", "s9", "s10", "s11", "t3", "t4", "t5", "t6"};

int main(int argc, char** argv) {
  auto ctx = std::make_unique<VerilatedContext>();
  ctx->commandArgs(argc, argv);
  auto top = std::make_unique<Vsoc_top>(ctx.get());

  const bool trace = ctx->commandArgsPlusMatch("trace")[0] != '\0';
  long max_cycles = 100000;
  if (const char* m = ctx->commandArgsPlusMatch("max="); m[0]) max_cycles = std::strtol(m + 5, nullptr, 10);
  bool want_a0 = false;
  uint32_t expect_a0 = 0;
  if (const char* e = ctx->commandArgsPlusMatch("expect_a0="); e[0]) {
    want_a0 = true;
    expect_a0 = (uint32_t)std::strtoul(e + 11, nullptr, 16);
  }
  struct MemCheck { uint32_t addr, val; };
  std::vector<MemCheck> mem_checks;
  for (int i = 1; i < argc; ++i)
    if (std::strncmp(argv[i], "+expect_mem=", 12) == 0) {
      char* colon = nullptr;
      const uint32_t a = (uint32_t)std::strtoul(argv[i] + 12, &colon, 16);
      if (colon && *colon == ':') mem_checks.push_back({a, (uint32_t)std::strtoul(colon + 1, nullptr, 16)});
    }
  if (!ctx->commandArgsPlusMatch("prog=")[0]) {
    std::printf("用法：%s +prog=程序.hex [+trace] [+max=N] [+expect_a0=HEX]\n", argv[0]);
    return 2;
  }

  // 测试平台自己维护一份寄存器的“影子”，只看核的写回口，用来在结束时报告 a0
  uint32_t shadow[32] = {0};

  // 波形：每次 eval() 之后调用 dump(t)，记下这一刻所有信号的值；时间 t 每半拍加 1
  uint64_t t = 0;
#if VM_TRACE_FST
  std::unique_ptr<VerilatedFstC> wave;
  if (const char* w = ctx->commandArgsPlusMatch("wave="); w[0]) {
    ctx->traceEverOn(true);
    wave = std::make_unique<VerilatedFstC>();
    top->trace(wave.get(), 99);              // 99：记录 99 层以内的全部信号
    wave->open(w + 6);
  }
  auto dump = [&]() { if (wave) wave->dump(t); ++t; };
#else
  if (ctx->commandArgsPlusMatch("wave=")[0])
    std::printf("提示：这个版本没有编进波形支持，+wave 被忽略。用 make wave PROG=... 编译带波形的版本\n");
  auto dump = [&]() { ++t; };
#endif

  // 复位：rst_n 拉低两拍再释放
  top->clk = 0; top->rst_n = 0; top->eval(); dump();
  for (int i = 0; i < 2; ++i) { top->clk = 1; top->eval(); dump(); top->clk = 0; top->eval(); dump(); }
  top->rst_n = 1; top->eval();

  std::string why = "超时（可能死循环，或者没有 ebreak）";
  long cycle = 0;
  for (; cycle < max_cycles; ++cycle) {
    top->clk = 0; top->eval(); dump();       // 组合逻辑稳定：本周期这条指令的所有信号都可见
    const uint32_t pc = top->dbg_pc, inst = top->dbg_inst;
    if (pc & 3) { why = "PC 没有 4 字节对齐（jalr 的目标没清最低位？跳转目标算错？）"; break; }
    if (top->imem_oob) { why = "取指越界（PC 跑出了存储器范围）"; break; }
    if (top->dbg_illegal) { why = "非法指令"; break; }
    if (trace) {
      std::printf("%6ld  pc=%08x  inst=%08x", cycle, pc, inst);
      if (top->dbg_rf_we && top->dbg_rd != 0)
        std::printf("  %-4s <- %08x", kAbi[top->dbg_rd], top->dbg_wdata);
      if (top->dbg_dmem_wmask)
        std::printf("  mem[%08x] mask=%x <- %08x", top->dbg_dmem_addr, top->dbg_dmem_wmask, top->dbg_dmem_wdata);
      std::printf("\n");
    }
    if (top->dbg_halt) { why = "ebreak"; break; }
    if (top->dmem_oob) { why = "写存储器越界"; break; }
    if (top->dbg_rf_we && top->dbg_rd != 0) shadow[top->dbg_rd] = top->dbg_wdata;
    top->clk = 1; top->eval(); dump();       // 上升沿：PC、寄存器堆、存储器同时更新
  }
  // 停下的那一拍只记了 clk 低；按原值再记一个时间点，波形里最后一拍才有宽度。
  // 不能再给上升沿：那样 PC 会往前走一步，下面报告的停止位置就错了
  dump();

  bool ok = (why == "ebreak");
  std::printf("CORE: %s，共 %ld 条指令，停在 pc=%08x inst=%08x，a0 = %08x (%d)",
              why.c_str(), cycle, top->dbg_pc, top->dbg_inst, shadow[10], (int32_t)shadow[10]);
  if (want_a0) {
    std::printf("，期望 a0 = %08x", expect_a0);
    ok = ok && shadow[10] == expect_a0;
  }
  // 存储器检查：直接读仿真存储器 ram（它不是你写的 RTL，测试平台可以看）
  for (const MemCheck& m : mem_checks) {
    const uint32_t idx = (m.addr - 0x80000000u) >> 2;
    const uint32_t got = idx < 16384 ? top->rootp->soc_top__DOT__u_mem__DOT__ram[idx] : 0xdeadbeefu;
    std::printf("\n  mem[%08x] = %08x，期望 %08x%s", m.addr, got, m.val, got == m.val ? "" : "  <- 不一致");
    ok = ok && got == m.val;
  }
  std::printf(" -> %s\n", ok ? "PASS" : "FAIL");
  top->final();
#if VM_TRACE_FST
  if (wave) wave->close();
#endif
  return ok ? 0 : 1;
}
