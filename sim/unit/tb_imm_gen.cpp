// 立即数生成单元测试：五种格式 × （定向指令 + 随机 32 位），与按规范手写的参考模型逐个对拍
#include <cstdint>
#include <cstdio>
#include <memory>
#include <random>
#include "Vimm_gen.h"
#include "verilated.h"

enum : uint8_t { IMM_I = 0, IMM_S = 1, IMM_B = 2, IMM_U = 3, IMM_J = 4 };
static const char* kName[] = {"I", "S", "B", "U", "J"};

static uint32_t bits(uint32_t x, int hi, int lo) { return (x >> lo) & ((1u << (hi - lo + 1)) - 1); }
static int32_t sext(uint32_t v, int n) { return (int32_t)(v << (32 - n)) >> (32 - n); }

// 参考模型：逐位照规范第 2.3 节的图拼，故意不写成和 RTL 一样的拼接式
static uint32_t ref(uint8_t sel, uint32_t x) {
  switch (sel) {
    case IMM_I: return (uint32_t)sext(bits(x, 31, 20), 12);
    case IMM_S: return (uint32_t)sext(bits(x, 31, 25) << 5 | bits(x, 11, 7), 12);
    case IMM_B: return (uint32_t)sext(bits(x, 31, 31) << 12 | bits(x, 7, 7) << 11 |
                                      bits(x, 30, 25) << 5 | bits(x, 11, 8) << 1, 13);
    case IMM_U: return x & 0xfffff000u;
    case IMM_J: return (uint32_t)sext(bits(x, 31, 31) << 20 | bits(x, 19, 12) << 12 |
                                      bits(x, 20, 20) << 11 | bits(x, 30, 21) << 1, 21);
  }
  return 0;
}

int main(int argc, char** argv) {
  auto ctx = std::make_unique<VerilatedContext>();
  ctx->commandArgs(argc, argv);
  auto dut = std::make_unique<Vimm_gen>(ctx.get());
  long total = 0, fails = 0;

  auto check = [&](uint8_t sel, uint32_t x, const char* tag) {
    dut->imm_sel = sel; dut->inst = x; dut->eval();
    const uint32_t want = ref(sel, x);
    ++total;
    if (dut->imm != want && ++fails <= 10)
      std::printf("  FAIL %s 型 %-14s inst=0x%08x  got 0x%08x (%d)  want 0x%08x (%d)\n",
                  kName[sel], tag, x, dut->imm, (int32_t)dut->imm, want, (int32_t)want);
  };

  // 定向：真实指令（编码已用 GNU as 核对），覆盖正负数和每一段立即数位
  struct { uint8_t sel; uint32_t x; const char* tag; } dir[] = {
    {IMM_I, 0x00150713, "addi +1"},      {IMM_I, 0xfff44683, "lbu -1"},
    {IMM_I, 0x7ff00093, "addi +2047"},   {IMM_I, 0x80000093, "addi -2048"},
    {IMM_S, 0x00f12623, "sw +12"},       {IMM_S, 0xfeb50e23, "sb -4"},
    {IMM_S, 0x7e000fa3, "sb +2047"},     {IMM_S, 0x80000023, "sb -2048"},
    {IMM_B, 0xfeb50ae3, "beq -12"},      {IMM_B, 0x00b55463, "bge +8"},
    {IMM_B, 0x7e000fe3, "beq +4094"},    {IMM_B, 0x80000063, "beq -4096"},
    {IMM_U, 0x80000537, "lui 0x80000"},  {IMM_U, 0x00010117, "auipc 0x10"},
    {IMM_J, 0x001000ef, "jal +2048"},    {IMM_J, 0x7ffff06f, "jal +1048574"},
    {IMM_J, 0x8000006f, "jal -1048576"}, {IMM_J, 0xffdff06f, "jal -4"},
  };
  for (auto& d : dir) check(d.sel, d.x, d.tag);

  // 单个 1：每种格式把 32 个位轮流置 1，能精确定位“哪一位接错了”
  for (uint8_t sel = 0; sel < 5; ++sel)
    for (int b = 0; b < 32; ++b) {
      char tag[16]; std::snprintf(tag, sizeof tag, "只有 bit%d", b);
      check(sel, 1u << b, tag);
    }

  // 随机：每种格式 20 万条
  std::mt19937 rng(20261014);
  for (uint8_t sel = 0; sel < 5; ++sel)
    for (int i = 0; i < 200000; ++i) check(sel, rng(), "随机");

  dut->final();
  std::printf("ImmGen: %ld cases, %ld failed -> %s\n", total, fails, fails ? "FAIL" : "PASS");
  return fails ? 1 : 0;
}
