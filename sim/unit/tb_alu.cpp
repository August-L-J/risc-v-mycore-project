// ALU 单元测试：定向用例 + 随机激励，与 C++ 参考模型逐个对拍
#include <cstdint>
#include <cstdio>
#include <memory>
#include <random>
#include "Valu.h"
#include "verilated.h"

enum : uint8_t {
  ADD = 0x0, SUB = 0x8, SLL = 0x1, SLT = 0x2, SLTU = 0x3,
  XOR = 0x4, SRL = 0x5, SRA = 0xD, OR = 0x6, AND = 0x7
};
static const uint8_t kOps[] = {ADD, SUB, SLL, SLT, SLTU, XOR, SRL, SRA, OR, AND};

static const char* name(uint8_t op) {
  switch (op) {
    case ADD: return "ADD";  case SUB: return "SUB";  case SLL: return "SLL";
    case SLT: return "SLT";  case SLTU: return "SLTU"; case XOR: return "XOR";
    case SRL: return "SRL";  case SRA: return "SRA";  case OR: return "OR";
    case AND: return "AND";  default: return "?";
  }
}

// 参考模型：直接照 RISC-V 规范写，故意不和 RTL 共享任何代码
static uint32_t ref(uint8_t op, uint32_t a, uint32_t b) {
  const unsigned sh = b & 31;
  switch (op) {
    case ADD:  return a + b;
    case SUB:  return a - b;
    case SLL:  return a << sh;
    case SLT:  return (int32_t)a < (int32_t)b ? 1 : 0;
    case SLTU: return a < b ? 1 : 0;
    case XOR:  return a ^ b;
    case SRL:  return a >> sh;
    case SRA:  return (uint32_t)((int32_t)a >> sh);
    case OR:   return a | b;
    case AND:  return a & b;
  }
  return 0;
}

int main(int argc, char** argv) {
  auto ctx = std::make_unique<VerilatedContext>();
  ctx->commandArgs(argc, argv);
  auto dut = std::make_unique<Valu>(ctx.get());

  long total = 0, fails = 0;
  auto check = [&](uint8_t op, uint32_t a, uint32_t b) {
    dut->op = op; dut->a = a; dut->b = b;
    dut->eval();
    const uint32_t want = ref(op, a, b);
    ++total;
    if (dut->y != want) {
      if (++fails <= 10)
        std::printf("  FAIL %-4s a=0x%08x b=0x%08x  got 0x%08x  want 0x%08x\n",
                    name(op), a, b, dut->y, want);
    }
  };

  // 边界值：0、1、-1、最大正数、最小负数，以及移位量 0/1/31/32（32 只看低 5 位，等于 0）
  const uint32_t edge[] = {0, 1, 2, 0x7fffffff, 0x80000000, 0xffffffff, 0xfffffffe,
                           31, 32, 33, 0x12345678, 0x87654321, 0x55555555, 0xaaaaaaaa};
  for (uint8_t op : kOps)
    for (uint32_t a : edge)
      for (uint32_t b : edge) check(op, a, b);

  std::mt19937 rng(20261010);
  for (int i = 0; i < 200000; ++i) check(kOps[rng() % 10], rng(), rng());

  dut->final();
  std::printf("ALU: %ld cases, %ld failed -> %s\n", total, fails, fails ? "FAIL" : "PASS");
  return fails ? 1 : 0;
}
