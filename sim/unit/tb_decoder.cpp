// 译码器单元测试：40 条 RV32I 指令 × 随机操作数 + 非法指令，与参考模型（L2 控制信号表）逐个对拍
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <memory>
#include <random>
#include <string>
#include "Vdecoder.h"
#include "verilated.h"

// 与 core_pkg.sv 的编码一致
enum { IMM_I = 0, IMM_S, IMM_B, IMM_U, IMM_J };
enum { A_RS1 = 0, A_PC, A_ZERO };
enum { B_RS2 = 0, B_IMM };
enum { WB_ALU = 0, WB_MEM, WB_PC4 };
enum { ADD = 0x0, SUB = 0x8, SLL = 0x1, SLT = 0x2, SLTU = 0x3, XOR = 0x4, SRL = 0x5, SRA = 0xD, OR = 0x6, AND = 0x7 };
constexpr int X = -1;  // 无关项：这条指令不用这个信号，测试不检查

struct Ctrl {
  int rf_we, imm_sel, alu_a_sel, alu_b_sel, alu_op, wb_sel, mem_we, mem_re, mem_size, is_br, is_jal, is_jalr, halt, illegal;
};
static const char* kSig[] = {"rf_we", "imm_sel", "alu_a_sel", "alu_b_sel", "alu_op", "wb_sel", "mem_we",
                             "mem_re", "mem_size", "is_br", "is_jal", "is_jalr", "halt", "illegal"};

static uint32_t bits(uint32_t x, int hi, int lo) { return (x >> lo) & ((1u << (hi - lo + 1)) - 1); }

// 参考模型：先认出是哪条指令，再查 L2 控制信号表。非法时只规定 illegal=1 且所有“有副作用”的信号为 0
static bool ref(uint32_t x, Ctrl& c, std::string& name) {
  const uint32_t op = bits(x, 6, 0), f3 = bits(x, 14, 12), f7 = bits(x, 31, 25);
  // 默认：不写、不访存、不跳、不停机、合法；其余为无关项
  c = {0, X, X, X, X, X, 0, 0, X, 0, 0, 0, 0, 0};
  auto bad = [&](const char* why) { c = {0, X, X, X, X, X, 0, 0, X, 0, 0, 0, 0, 1}; name = why; return false; };
  static const char* rN[8] = {"add", "sll", "slt", "sltu", "xor", "srl", "or", "and"};
  static const char* iN[8] = {"addi", "slli", "slti", "sltiu", "xori", "srli", "ori", "andi"};
  switch (op) {
    case 0x33:  // R 型
      if (f7 == 0x00) { name = rN[f3]; }
      else if (f7 == 0x20 && (f3 == 0 || f3 == 5)) { name = f3 == 0 ? "sub" : "sra"; }
      else return bad("R 型 funct7 非法");
      c.rf_we = 1; c.alu_a_sel = A_RS1; c.alu_b_sel = B_RS2; c.alu_op = (bits(x, 30, 30) << 3) | f3; c.wb_sel = WB_ALU;
      return true;
    case 0x13:  // I 型运算
      if (f3 == 1 && f7 != 0x00) return bad("slli 的 funct7 必须为 0");
      if (f3 == 5 && f7 != 0x00 && f7 != 0x20) return bad("srli/srai 的 funct7 只能是 0 或 0x20");
      name = (f3 == 5 && f7 == 0x20) ? "srai" : iN[f3];
      c.rf_we = 1; c.imm_sel = IMM_I; c.alu_a_sel = A_RS1; c.alu_b_sel = B_IMM; c.wb_sel = WB_ALU;
      c.alu_op = (f3 == 1 || f3 == 5) ? ((bits(x, 30, 30) << 3) | f3) : f3;  // 只有移位看 inst[30]
      return true;
    case 0x03:  // load
      if (f3 == 3 || f3 >= 6) return bad("load 的 funct3 非法");
      { static const char* n[] = {"lb", "lh", "lw", "", "lbu", "lhu"}; name = n[f3]; }
      c.rf_we = 1; c.imm_sel = IMM_I; c.alu_a_sel = A_RS1; c.alu_b_sel = B_IMM; c.alu_op = ADD; c.wb_sel = WB_MEM;
      c.mem_re = 1; c.mem_size = f3;
      return true;
    case 0x23:  // store
      if (f3 > 2) return bad("store 的 funct3 非法");
      { static const char* n[] = {"sb", "sh", "sw"}; name = n[f3]; }
      c.imm_sel = IMM_S; c.alu_a_sel = A_RS1; c.alu_b_sel = B_IMM; c.alu_op = ADD; c.mem_we = 1; c.mem_size = f3;
      return true;
    case 0x63:  // 分支
      if (f3 == 2 || f3 == 3) return bad("分支的 funct3 非法");
      { static const char* n[] = {"beq", "bne", "", "", "blt", "bge", "bltu", "bgeu"}; name = n[f3]; }
      c.imm_sel = IMM_B; c.alu_a_sel = A_PC; c.alu_b_sel = B_IMM; c.alu_op = ADD; c.is_br = 1;
      return true;
    case 0x6f:
      name = "jal";
      c.rf_we = 1; c.imm_sel = IMM_J; c.alu_a_sel = A_PC; c.alu_b_sel = B_IMM; c.alu_op = ADD; c.wb_sel = WB_PC4; c.is_jal = 1;
      return true;
    case 0x67:
      if (f3 != 0) return bad("jalr 的 funct3 必须为 0");
      name = "jalr";
      c.rf_we = 1; c.imm_sel = IMM_I; c.alu_a_sel = A_RS1; c.alu_b_sel = B_IMM; c.alu_op = ADD; c.wb_sel = WB_PC4; c.is_jalr = 1;
      return true;
    case 0x37:
      name = "lui";
      c.rf_we = 1; c.imm_sel = IMM_U; c.alu_a_sel = A_ZERO; c.alu_b_sel = B_IMM; c.alu_op = ADD; c.wb_sel = WB_ALU;
      return true;
    case 0x17:
      name = "auipc";
      c.rf_we = 1; c.imm_sel = IMM_U; c.alu_a_sel = A_PC; c.alu_b_sel = B_IMM; c.alu_op = ADD; c.wb_sel = WB_ALU;
      return true;
    case 0x0f:  // fence：在单周期核里什么都不做
      if (f3 != 0) return bad("funct3 != 0（fence.i 属于 Zifencei，不在 RV32I）");
      name = "fence";
      return true;
    case 0x73:  // ecall / ebreak：其余字段必须全 0
      if (f3 != 0 || bits(x, 11, 7) != 0 || bits(x, 19, 15) != 0 || bits(x, 31, 21) != 0)
        return bad("系统指令编码非法（CSR 指令属于 Zicsr）");
      name = bits(x, 20, 20) ? "ebreak" : "ecall";
      c.halt = bits(x, 20, 20);
      return true;
    default:
      return bad("opcode 不属于 RV32I");
  }
}

int main(int argc, char** argv) {
  auto ctx = std::make_unique<VerilatedContext>();
  ctx->commandArgs(argc, argv);
  auto dut = std::make_unique<Vdecoder>(ctx.get());
  long total = 0, fails = 0;
  int seen[64] = {0};
  std::string names[64];
  int nNames = 0;

  auto check = [&](uint32_t x) {
    Ctrl want; std::string name;
    ref(x, want, name);
    dut->inst = x; dut->eval();
    const int got[14] = {dut->rf_we, dut->imm_sel, dut->alu_a_sel, dut->alu_b_sel, dut->alu_op, dut->wb_sel, dut->mem_we,
                         dut->mem_re, dut->mem_size, dut->is_br, dut->is_jal, dut->is_jalr, dut->halt, dut->illegal};
    const int* w = &want.rf_we;
    ++total;
    for (int k = 0; k < 14; ++k) {
      if (w[k] == X || got[k] == w[k]) continue;
      if (++fails <= 12)
        std::printf("  FAIL %-7s inst=0x%08x  %-9s got %d  want %d\n", name.c_str(), x, kSig[k], got[k], w[k]);
      break;
    }
    if (!want.illegal) {
      int i = 0;
      while (i < nNames && names[i] != name) ++i;
      if (i == nNames && nNames < 64) names[nNames++] = name;
      ++seen[i];
    }
  };

  // 1. 定向：每条指令一个真实编码（已用 GNU as 核对）
  const uint32_t dir[] = {
    0x00f50533, 0x40c58533, 0x00c59533, 0x00c5a533, 0x00c5b533, 0x00c5c533, 0x00c5d533, 0x40c5d533, 0x00c5e533, 0x00c5f533,
    0x00150713, 0x0015a713, 0x0015b713, 0x0015c713, 0x0015e713, 0x0015f713, 0x00379793, 0x0037d793, 0x4037d793,
    0x00c12503, 0x00c11503, 0x00c10503, 0xfff44683, 0x00c15503, 0x00f12623, 0x00f11623, 0xfeb50e23,
    0xfeb50ae3, 0x00b51463, 0x00b54463, 0x00b55463, 0x00b56463, 0x00b57463,
    0x001000ef, 0x008280e7, 0x80000537, 0x00010117, 0x0ff0000f, 0x00000073, 0x00100073,
  };
  for (uint32_t x : dir) check(x);

  // 2. 随机：对每个合法的 (opcode, funct3, funct7) 组合，随机填其余的位（寄存器号、立即数）
  std::mt19937 rng(20261014);
  struct Tpl { uint32_t op; int f3; int f7; };  // f3/f7 = -1 表示这几位属于立即数，随机
  const Tpl tpl[] = {
    {0x33, 0, 0x00}, {0x33, 0, 0x20}, {0x33, 1, 0x00}, {0x33, 2, 0x00}, {0x33, 3, 0x00}, {0x33, 4, 0x00},
    {0x33, 5, 0x00}, {0x33, 5, 0x20}, {0x33, 6, 0x00}, {0x33, 7, 0x00},
    {0x13, 0, -1}, {0x13, 2, -1}, {0x13, 3, -1}, {0x13, 4, -1}, {0x13, 6, -1}, {0x13, 7, -1},
    {0x13, 1, 0x00}, {0x13, 5, 0x00}, {0x13, 5, 0x20},
    {0x03, 0, -1}, {0x03, 1, -1}, {0x03, 2, -1}, {0x03, 4, -1}, {0x03, 5, -1},
    {0x23, 0, -1}, {0x23, 1, -1}, {0x23, 2, -1},
    {0x63, 0, -1}, {0x63, 1, -1}, {0x63, 4, -1}, {0x63, 5, -1}, {0x63, 6, -1}, {0x63, 7, -1},
    {0x6f, -1, -1}, {0x67, 0, -1}, {0x37, -1, -1}, {0x17, -1, -1},
  };
  for (const Tpl& t : tpl)
    for (int i = 0; i < 5000; ++i) {
      uint32_t x = (rng() & ~0x7fu) | t.op;
      if (t.f3 >= 0) x = (x & ~(7u << 12)) | (uint32_t)t.f3 << 12;
      if (t.f7 >= 0) x = (x & ~(0x7fu << 25)) | (uint32_t)t.f7 << 25;
      check(x);
    }

  // 3. 非法指令：保留的 opcode、非法 funct3/funct7、全 0、全 1、CSR 指令、fence.i
  const uint32_t bad[] = {
    0x00000000, 0xffffffff,                         // 全 0、全 1：规范明确规定为非法
    0x02c58533,                                     // mul（M 扩展，funct7=1）
    0x40c59533, 0x40c5c533,                         // sll/xor 配 funct7=0x20
    0x40379793, 0x0237d793,                         // slli funct7=0x20、srli funct7=0x01
    0x00c13503, 0x00c16503,                         // load funct3=011、110
    0x00f13623,                                     // store funct3=011
    0x00b52463, 0x00b53463,                         // 分支 funct3=010、011
    0x008290e7,                                     // jalr funct3=001
    0x0000100f,                                     // fence.i
    0x30002573, 0x00100173,                         // csrr、ebreak 但 rd≠0
    0x00200073, 0x30200073, 0x10500073, 0xfff00073, // 只有 inst[31:20] 不对：值为 2、mret、wfi、全 1
    0x0000000b, 0x0000002f, 0x00000053, 0x0000005b, 0x0000007b, 0x00000012,  // 其他 opcode
  };
  for (uint32_t x : bad) check(x);
  // 所有 128 个 opcode 都试一遍（其余位随机）
  for (uint32_t op = 0; op < 128; ++op)
    for (int i = 0; i < 200; ++i) check((rng() & ~0x7fu) | op);
  // 完全随机的 32 位
  for (int i = 0; i < 100000; ++i) check(rng());

  dut->final();
  std::printf("Decoder: %ld cases, %d instructions covered, %ld failed -> %s\n", total, nNames, fails,
              fails ? "FAIL" : (nNames == 40 ? "PASS" : "FAIL（覆盖不到 40 条）"));
  return (fails || nNames != 40) ? 1 : 0;
}
