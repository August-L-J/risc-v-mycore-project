// 寄存器堆单元测试：x0 写保护、读组合/写时钟沿、同周期读写、随机读写与参考模型对拍
#include <cstdint>
#include <cstdio>
#include <memory>
#include <random>
#include "Vregfile.h"
#include "verilated.h"

static std::unique_ptr<VerilatedContext> ctx;
static std::unique_ptr<Vregfile> dut;
static uint32_t model[32];
static long total = 0, fails = 0;

static void fail(const char* what, uint32_t got, uint32_t want) {
  ++fails;
  if (fails <= 10) std::printf("  FAIL %s  got 0x%08x  want 0x%08x\n", what, got, want);
}

// 一个完整时钟周期：下降沿设好输入，上升沿完成写入
static void tick() {
  dut->clk = 0; dut->eval();
  dut->clk = 1; dut->eval();
  dut->clk = 0; dut->eval();
}

static void read_check(int r1, int r2) {
  dut->raddr1 = r1; dut->raddr2 = r2; dut->eval();
  ++total;
  if (dut->rdata1 != model[r1]) fail("rdata1", dut->rdata1, model[r1]);
  if (dut->rdata2 != model[r2]) fail("rdata2", dut->rdata2, model[r2]);
}

int main(int argc, char** argv) {
  ctx = std::make_unique<VerilatedContext>();
  ctx->commandArgs(argc, argv);
  dut = std::make_unique<Vregfile>(ctx.get());
  char buf[96];

  dut->clk = 0; dut->we = 0; dut->waddr = 0; dut->wdata = 0; dut->eval();

  // 1. 先把 x1～x31 全部写成已知值，x0 保持 0
  for (int i = 1; i < 32; ++i) {
    dut->we = 1; dut->waddr = i; dut->wdata = model[i] = 0x1000u * i + i;
    tick();
  }
  dut->we = 0;
  for (int i = 0; i < 32; ++i) read_check(i, 31 - i);

  // 2. x0 写保护：写 x0 之后读出来必须还是 0
  dut->we = 1; dut->waddr = 0; dut->wdata = 0xdeadbeef; tick(); dut->we = 0;
  ++total;
  dut->raddr1 = 0; dut->raddr2 = 0; dut->eval();
  if (dut->rdata1 != 0 || dut->rdata2 != 0) fail("x0 被写坏了", dut->rdata1, 0);

  // 3. we = 0 时不能写
  dut->we = 0; dut->waddr = 5; dut->wdata = 0xbad0bad0; tick();
  read_check(5, 5);

  // 4. 读是组合的：同一周期里，上升沿之前读到旧值，上升沿之后读到新值
  dut->raddr1 = 7; dut->raddr2 = 7;
  dut->we = 1; dut->waddr = 7; dut->wdata = 0xcafef00d;
  dut->clk = 0; dut->eval();
  ++total;
  if (dut->rdata1 != model[7]) fail("上升沿前应读到旧值", dut->rdata1, model[7]);
  dut->clk = 1; dut->eval();
  model[7] = 0xcafef00d;
  ++total;
  if (dut->rdata1 != model[7]) fail("上升沿后应读到新值", dut->rdata1, model[7]);
  dut->clk = 0; dut->we = 0; dut->eval();

  // 5. 随机：每个周期随机写一个寄存器、随机读两个
  std::mt19937 rng(20261010);
  for (int i = 0; i < 100000; ++i) {
    const int r1 = rng() % 32, r2 = rng() % 32, w = rng() % 32;
    const bool we = rng() % 4 != 0;
    const uint32_t v = rng();
    dut->raddr1 = r1; dut->raddr2 = r2;
    dut->we = we; dut->waddr = w; dut->wdata = v;
    dut->clk = 0; dut->eval();
    ++total;
    if (dut->rdata1 != model[r1]) { std::snprintf(buf, sizeof buf, "随机 第%d拍 rdata1(x%d)", i, r1); fail(buf, dut->rdata1, model[r1]); }
    if (dut->rdata2 != model[r2]) { std::snprintf(buf, sizeof buf, "随机 第%d拍 rdata2(x%d)", i, r2); fail(buf, dut->rdata2, model[r2]); }
    dut->clk = 1; dut->eval();
    if (we && w != 0) model[w] = v;
  }

  dut->final();
  std::printf("RegFile: %ld checks, %ld failed -> %s\n", total, fails, fails ? "FAIL" : "PASS");
  return fails ? 1 : 0;
}
