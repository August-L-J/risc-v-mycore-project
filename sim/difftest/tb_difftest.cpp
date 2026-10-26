// DiffTest 测试平台：核和参考模型同步执行，每提交一条指令就比对一次
//
// 用法：Vsoc_top +prog=xxx.hex [+max=N] [+itrace] [+itrace_n=K] [+expect_a0=HEX]
//   +itrace       每条指令打印一行反汇编（参考模型给出的“应该执行什么”）
//   +itrace_n=K   出错时回看最近 K 条指令（默认 16），这就是一生一芯说的环形缓冲 iringbuf
//   +expect_a0=   和 tb_core 一样，结束时再检查 a0；不给就只看 DiffTest 有没有报错
//
// 比对内容（每条指令一次，在上升沿之前、核的组合逻辑已稳定时）：
//   PC、指令编码、是否写寄存器、写哪个寄存器、写的值、是否写存储器、写的地址 / 掩码 / 数据、
//   是否 halt / illegal。第一处不一致就停下，打印两边的差异和最近 K 条指令。
//
// 核只通过 dbg_* 端口观察，不读 RTL 内部信号；参考模型是 ref_rv32i.h，按规范逐条执行。
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <memory>
#include <string>
#include <vector>
#include "Vsoc_top.h"
#include "verilated.h"
#include "ref_rv32i.h"

static const char* kAbi[32] = {"zero", "ra", "sp", "gp", "tp", "t0", "t1", "t2", "s0", "s1", "a0",
                               "a1",   "a2", "a3", "a4", "a5", "a6", "a7", "s2", "s3", "s4", "s5",
                               "s6",   "s7", "s8", "s9", "s10", "s11", "t3", "t4", "t5", "t6"};

// 把核这一拍的 dbg_* 端口整理成和参考模型一样的提交记录，方便逐项比较
static RefRV32I::Commit dut_commit(const Vsoc_top& t) {
  RefRV32I::Commit c;
  c.pc = t.dbg_pc;
  c.inst = t.dbg_inst;
  c.rf_we = t.dbg_rf_we && t.dbg_rd != 0;          // 写 x0 等于没写，两边都这样约定
  c.rd = c.rf_we ? t.dbg_rd : 0;
  c.wdata = c.rf_we ? t.dbg_wdata : 0;
  c.mem_we = t.dbg_dmem_wmask != 0;
  c.maddr = c.mem_we ? t.dbg_dmem_addr : 0;
  c.wmask = c.mem_we ? t.dbg_dmem_wmask : 0;
  // 存储器只比较被写的那些字节：没被 wmask 选中的字节核里是什么都无所谓
  uint32_t keep = 0;
  for (int j = 0; j < 4; ++j) if (c.wmask >> j & 1) keep |= 0xffu << 8 * j;
  c.mdata = c.mem_we ? (t.dbg_dmem_wdata & keep) : 0;
  c.halt = t.dbg_halt;
  c.illegal = t.dbg_illegal;
  return c;
}

static std::string describe(const RefRV32I::Commit& c) {
  char s[160];
  int n = std::snprintf(s, sizeof s, "pc=%08x inst=%08x", c.pc, c.inst);
  if (c.rf_we) n += std::snprintf(s + n, sizeof s - n, "  %s <- %08x", kAbi[c.rd], c.wdata);
  if (c.mem_we) n += std::snprintf(s + n, sizeof s - n, "  mem[%08x] mask=%x <- %08x", c.maddr, c.wmask, c.mdata);
  if (c.halt) n += std::snprintf(s + n, sizeof s - n, "  halt");
  if (c.illegal) n += std::snprintf(s + n, sizeof s - n, "  illegal");
  return s;
}

int main(int argc, char** argv) {
  auto ctx = std::make_unique<VerilatedContext>();
  ctx->commandArgs(argc, argv);
  auto top = std::make_unique<Vsoc_top>(ctx.get());

  // 注意：commandArgsPlusMatch 返回的字符串放在同一块 thread_local 缓冲里，下一次调用就会被覆盖，
  // 所以要马上复制成 std::string，不能把指针留到后面再用
  const std::string prog = ctx->commandArgsPlusMatch("prog=");
  if (prog.empty()) { std::printf("用法：%s +prog=程序.hex [+itrace] [+itrace_n=K] [+max=N] [+expect_a0=HEX]\n", argv[0]); return 2; }
  long max_cycles = 500000;
  if (const char* m = ctx->commandArgsPlusMatch("max="); m[0]) max_cycles = std::strtol(m + 5, nullptr, 10);
  // commandArgsPlusMatch 是前缀匹配，"itrace" 也会匹配到 "+itrace_n=8"，所以这里自己精确比较
  bool itrace = false;
  for (int k = 1; k < argc; ++k) if (std::string(argv[k]) == "+itrace") itrace = true;
  size_t ring_n = 16;
  if (const char* k = ctx->commandArgsPlusMatch("itrace_n="); k[0]) ring_n = std::strtoul(k + 10, nullptr, 10);
  bool want_a0 = false;
  uint32_t expect_a0 = 0;
  if (const char* e = ctx->commandArgsPlusMatch("expect_a0="); e[0]) { want_a0 = true; expect_a0 = (uint32_t)std::strtoul(e + 11, nullptr, 16); }

  // 参考模型读同一个 hex 文件（mem.sv 也是在构造模型时 $readmemh 读它）
  RefRV32I ref;
  std::string err;
  if (!ref.load_hex(prog.c_str() + 6, &err)) { std::printf("DIFFTEST: %s\n", err.c_str()); return 2; }

  // 复位：和 tb_core 完全一样
  top->clk = 0; top->rst_n = 0; top->eval();
  for (int i = 0; i < 2; ++i) { top->clk = 1; top->eval(); top->clk = 0; top->eval(); }
  top->rst_n = 1; top->eval();

  // 最近 ring_n 条指令的环形缓冲（iringbuf），出错时回看。
  // 平时只存 (序号, pc, inst) 三个数，出错时才反汇编：每条都格式化字符串会让速度慢一倍多
  struct RingItem { long n; uint32_t pc, inst; };
  std::vector<RingItem> ring(ring_n ? ring_n : 1);
  size_t ring_pos = 0, ring_cnt = 0;
  auto ring_line = [](const RingItem& it) {
    char s[200];
    std::snprintf(s, sizeof s, "%6ld  %08x  %08x  %s", it.n, it.pc, it.inst, RefRV32I::disasm(it.inst).c_str());
    return std::string(s);
  };

  long cycle = 0;
  std::string verdict = "超时（可能死循环，或者没有 ebreak）";
  bool ok = false;
  for (; cycle < max_cycles; ++cycle) {
    top->clk = 0; top->eval();                       // 核：组合逻辑稳定，这一拍的 dbg_* 可读
    const RefRV32I::Commit d = dut_commit(*top);
    const RefRV32I::Commit r = ref.step();           // 参考模型：执行同一条指令

    const RingItem item{cycle, r.pc, r.inst};
    if (itrace) std::printf("%s\n", ring_line(item).c_str());
    ring[ring_pos] = item; ring_pos = (ring_pos + 1) % ring.size(); if (ring_cnt < ring.size()) ++ring_cnt;

    // 逐项比较，第一处不同就停
    std::vector<std::string> diff;
    auto chk = [&](const char* what, uint32_t dv, uint32_t rv) {
      if (dv != rv) { char s[96]; std::snprintf(s, sizeof s, "%-8s 核 = %08x，参考 = %08x", what, dv, rv); diff.push_back(s); }
    };
    chk("pc", d.pc, r.pc);
    chk("inst", d.inst, r.inst);
    chk("illegal", d.illegal, r.illegal);
    chk("halt", d.halt, r.halt);
    if (d.pc == r.pc && d.inst == r.inst && !r.illegal) {
      chk("写寄存器", d.rf_we, r.rf_we);
      if (d.rf_we && r.rf_we) { chk("rd", d.rd, r.rd); chk("写回值", d.wdata, r.wdata); }
      chk("写存储器", d.mem_we, r.mem_we);
      if (d.mem_we && r.mem_we) { chk("地址", d.maddr, r.maddr); chk("wmask", d.wmask, r.wmask); chk("数据", d.mdata, r.mdata); }
    }

    if (!diff.empty()) {
      std::printf("DIFFTEST: 第 %ld 条指令不一致\n", cycle);
      std::printf("  参考：%s\n", describe(r).c_str());
      std::printf("  核  ：%s\n", describe(d).c_str());
      for (const auto& s : diff) std::printf("  ✗ %s\n", s.c_str());
      std::printf("  这条指令：%s\n", RefRV32I::disasm(r.inst).c_str());
      std::printf("  最近 %zu 条（最后一行就是出错的这条）：\n", ring_cnt);
      for (size_t k = 0; k < ring_cnt; ++k) std::printf("    %s\n", ring_line(ring[(ring_pos + ring.size() - ring_cnt + k) % ring.size()]).c_str());
      verdict = "DiffTest 不一致";
      break;
    }
    if (r.halt) { verdict = "ebreak"; ok = true; break; }
    if (r.illegal) { verdict = "非法指令（两边一致）"; break; }

    top->clk = 1; top->eval();                       // 核：上升沿，状态更新；参考模型已经在 step() 里更新过了
  }

  if (ok && want_a0 && ref.x[10] != expect_a0) {
    ok = false;
    char s[96]; std::snprintf(s, sizeof s, "ebreak，但 a0 = %08x，期望 %08x", ref.x[10], expect_a0); verdict = s;
  }
  // cycle 是最后一条的序号（从 0 数）；停在 ebreak、不一致、非法时这一条也比过了，所以 +1；只有超时是跑满 max 条
  const long compared = cycle < max_cycles ? cycle + 1 : cycle;
  std::printf("DIFFTEST: %s，比对了 %ld 条指令，a0 = %08x -> %s\n", verdict.c_str(), compared, ref.x[10], ok ? "PASS" : "FAIL");
  top->final();
  return ok ? 0 : 1;
}
