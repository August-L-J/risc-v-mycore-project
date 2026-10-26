// RV32I 参考模型（DiffTest 的“标准答案”）
//
// 用软件逐条执行和 RTL 完全相同的程序，每执行一条就产生一份“提交记录”
// （PC、指令、写了哪个寄存器什么值、写了存储器哪里），测试平台拿它和核的 dbg_* 端口比对。
//
// 刻意写成和 RTL 无关的样子：按规范逐条翻译，不看 rtl/ 里的任何实现，
// 这样两边犯同一个错的概率才小。只依赖 C++ 标准库，单头文件。
//
// 范围与 mycore 一致：RV32I 40 条 + fence（当 nop）+ ebreak（停机），
// 其余编码一律判为非法；64 KiB 存储器，基地址 0x80000000。
#pragma once
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

class RefRV32I {
 public:
  static constexpr uint32_t kBase = 0x80000000u;
  static constexpr uint32_t kWords = 16384;          // 64 KiB，和 sim/core/mem.sv 相同

  // 每条指令执行完的“提交记录”，和核的 dbg_* 端口一一对应
  struct Commit {
    uint32_t pc = 0, inst = 0;
    bool rf_we = false;   uint8_t rd = 0;  uint32_t wdata = 0;   // 写寄存器（rd = 0 时视为不写）
    bool mem_we = false;  uint32_t maddr = 0;  uint8_t wmask = 0;  uint32_t mdata = 0;  // 写存储器（字地址、字节掩码、对齐好的数据）
    bool halt = false, illegal = false;
    uint32_t next_pc = 0;
  };

  uint32_t pc = kBase;
  uint32_t x[32] = {0};
  std::vector<uint32_t> mem = std::vector<uint32_t>(kWords, 0);

  // 读 $readmemh 格式的 hex（每行一个 32 位字，可有 // 注释和 @地址），和 mem.sv 读同一个文件
  bool load_hex(const char* path, std::string* err) {
    FILE* f = std::fopen(path, "r");
    if (!f) { *err = std::string("打不开 ") + path; return false; }
    char line[256];
    uint32_t idx = 0;
    while (std::fgets(line, sizeof line, f)) {
      char* p = line;
      while (*p == ' ' || *p == '\t') ++p;
      if (*p == '\0' || *p == '\n' || *p == '\r' || (p[0] == '/' && p[1] == '/')) continue;
      if (*p == '@') { idx = (uint32_t)std::strtoul(p + 1, nullptr, 16); continue; }
      if (idx < kWords) mem[idx] = (uint32_t)std::strtoul(p, nullptr, 16);
      ++idx;
    }
    std::fclose(f);
    return true;
  }

  // 执行一条指令，返回提交记录。非法时 illegal = true，状态不变
  Commit step() {
    Commit c;
    c.pc = pc;
    c.inst = fetch(pc);
    const uint32_t i = c.inst;
    const uint32_t op = i & 0x7f, rd = (i >> 7) & 31, f3 = (i >> 12) & 7, rs1 = (i >> 15) & 31,
                   rs2 = (i >> 20) & 31, f7 = i >> 25;
    const uint32_t a = x[rs1], b = x[rs2];
    const int32_t imm_i = (int32_t)i >> 20;
    const int32_t imm_s = ((int32_t)i >> 25 << 5) | (int32_t)((i >> 7) & 31);
    const int32_t imm_b = ((int32_t)i >> 31 << 12) | (int32_t)(((i >> 7) & 1) << 11) |
                          (int32_t)(((i >> 25) & 0x3f) << 5) | (int32_t)(((i >> 8) & 0xf) << 1);
    const uint32_t imm_u = i & 0xfffff000u;
    const int32_t imm_j = ((int32_t)i >> 31 << 20) | (int32_t)(((i >> 12) & 0xff) << 12) |
                          (int32_t)(((i >> 20) & 1) << 11) | (int32_t)(((i >> 21) & 0x3ff) << 1);

    uint32_t npc = pc + 4;
    bool wr = false;
    uint32_t val = 0;
    auto bad = [&]() { c.illegal = true; c.next_pc = pc; return c; };

    switch (op) {
      case 0x37: wr = true; val = imm_u; break;                         // lui
      case 0x17: wr = true; val = pc + imm_u; break;                    // auipc
      case 0x6f: wr = true; val = pc + 4; npc = pc + imm_j; break;      // jal
      case 0x67:                                                        // jalr
        if (f3 != 0) return bad();
        wr = true; val = pc + 4; npc = (a + imm_i) & ~1u; break;
      case 0x63: {                                                      // 分支
        bool t;
        switch (f3) {
          case 0: t = a == b; break;
          case 1: t = a != b; break;
          case 4: t = (int32_t)a < (int32_t)b; break;  // blt rs1,rs2,imm 
          case 5: t = (int32_t)a >= (int32_t)b; break;
          case 6: t = a < b; break;
          case 7: t = a >= b; break;
          default: return bad();
        }
        if (t) npc = pc + imm_b;
        break;
      }
      case 0x03: {                                                      // load
        const uint32_t addr = a + imm_i, w = read_word(addr & ~3u), sh = 8 * (addr & 3);
        switch (f3) {
          case 0: val = (uint32_t)(int32_t)(int8_t)(w >> sh); break;    // lb
          case 1: val = (uint32_t)(int32_t)(int16_t)(w >> sh); break;   // lh
          case 2: val = w; break;                                       // lw
          case 4: val = (w >> sh) & 0xff; break;                        // lbu
          case 5: val = (w >> sh) & 0xffff; break;                      // lhu
          default: return bad();
        }
        wr = true;
        break;
      }
      case 0x23: {                                                      // store
        const uint32_t addr = a + imm_s, sh = 8 * (addr & 3);
        uint8_t m;
        uint32_t d;
        switch (f3) {
          case 0: m = (uint8_t)(1u << (addr & 3)); d = (b & 0xff) << sh; break;    // sb
          case 1: m = (uint8_t)(3u << (addr & 3)); d = (b & 0xffff) << sh; break;  // sh
          case 2: m = 0xf; d = b; break;                                           // sw
          default: return bad();
        }
        c.mem_we = true; c.maddr = addr & ~3u; c.wmask = m & 0xf; c.mdata = d;
        break;
      }
      case 0x13: {                                                      // I 型运算
        const uint32_t sh = rs2;                                        // shamt = imm[4:0]
        switch (f3) {
          case 0: val = a + imm_i; break;
          case 2: val = (int32_t)a < imm_i; break;
          case 3: val = a < (uint32_t)imm_i; break;
          case 4: val = a ^ imm_i; break;
          case 6: val = a | imm_i; break;
          case 7: val = a & imm_i; break;
          case 1: if (f7 != 0) return bad(); val = a << sh; break;
          case 5:
            if (f7 == 0x00) val = a >> sh;
            else if (f7 == 0x20) val = (uint32_t)((int32_t)a >> sh);
            else return bad();
            break;
        }
        wr = true;
        break;
      }
      case 0x33: {                                                      // R 型运算
        const uint32_t sh = b & 31;
        if (f7 == 0x00) {
          switch (f3) {
            case 0: val = a + b; break;
            case 1: val = a << sh; break;
            case 2: val = (int32_t)a < (int32_t)b; break;
            case 3: val = a < b; break;
            case 4: val = a ^ b; break;
            case 5: val = a >> sh; break;
            case 6: val = a | b; break;
            case 7: val = a & b; break;
          }
        } else if (f7 == 0x20 && f3 == 0) {
          val = a - b;
        } else if (f7 == 0x20 && f3 == 5) {
          val = (uint32_t)((int32_t)a >> sh);
        } else {
          return bad();
        }
        wr = true;
        break;
      }
      case 0x0f:                                                        // fence：单周期顺序执行，什么都不做
        if (f3 != 0) return bad();                                      // fence.i 属于 Zifencei，不支持
        break;
      case 0x73:                                                        // ecall / ebreak
        if (i == 0x00100073u) { c.halt = true; c.next_pc = pc; return c; }
        return bad();                                                   // ecall、CSR 指令：本阶段不支持
      default:
        return bad();
    }

    // 提交：写寄存器、写存储器、更新 PC
    if (wr && rd != 0) { x[rd] = val; c.rf_we = true; c.rd = (uint8_t)rd; c.wdata = val; }
    if (c.mem_we) write_word(c.maddr, c.mdata, c.wmask);
    pc = npc;
    c.next_pc = npc;
    return c;
  }

  // 反汇编一条指令，用于报错信息（只覆盖 RV32I，写法和 objdump -M no-aliases 一致）
  static std::string disasm(uint32_t i) {
    static const char* R[32] = {"zero", "ra", "sp", "gp", "tp", "t0", "t1", "t2", "s0", "s1", "a0",
                                "a1",   "a2", "a3", "a4", "a5", "a6", "a7", "s2", "s3", "s4", "s5",
                                "s6",   "s7", "s8", "s9", "s10", "s11", "t3", "t4", "t5", "t6"};
    const uint32_t op = i & 0x7f, rd = (i >> 7) & 31, f3 = (i >> 12) & 7, rs1 = (i >> 15) & 31,
                   rs2 = (i >> 20) & 31, f7 = i >> 25;
    const int32_t ii = (int32_t)i >> 20;
    const int32_t is = ((int32_t)i >> 25 << 5) | (int32_t)((i >> 7) & 31);
    const int32_t ib = ((int32_t)i >> 31 << 12) | (int32_t)(((i >> 7) & 1) << 11) |
                       (int32_t)(((i >> 25) & 0x3f) << 5) | (int32_t)(((i >> 8) & 0xf) << 1);
    const int32_t ij = ((int32_t)i >> 31 << 20) | (int32_t)(((i >> 12) & 0xff) << 12) |
                       (int32_t)(((i >> 20) & 1) << 11) | (int32_t)(((i >> 21) & 0x3ff) << 1);
    char s[64];
    static const char* BR[8] = {"beq", "bne", "?", "?", "blt", "bge", "bltu", "bgeu"};
    static const char* LD[8] = {"lb", "lh", "lw", "?", "lbu", "lhu", "?", "?"};
    static const char* ST[8] = {"sb", "sh", "sw", "?", "?", "?", "?", "?"};
    static const char* IA[8] = {"addi", "slli", "slti", "sltiu", "xori", "srli", "ori", "andi"};
    static const char* RA[8] = {"add", "sll", "slt", "sltu", "xor", "srl", "or", "and"};
    switch (op) {
      case 0x37: std::snprintf(s, sizeof s, "lui %s,0x%x", R[rd], i >> 12); break;
      case 0x17: std::snprintf(s, sizeof s, "auipc %s,0x%x", R[rd], i >> 12); break;
      case 0x6f: std::snprintf(s, sizeof s, "jal %s,%d", R[rd], ij); break;
      case 0x67: std::snprintf(s, sizeof s, "jalr %s,%d(%s)", R[rd], ii, R[rs1]); break;
      case 0x63: std::snprintf(s, sizeof s, "%s %s,%s,%d", BR[f3], R[rs1], R[rs2], ib); break;
      case 0x03: std::snprintf(s, sizeof s, "%s %s,%d(%s)", LD[f3], R[rd], ii, R[rs1]); break;
      case 0x23: std::snprintf(s, sizeof s, "%s %s,%d(%s)", ST[f3], R[rs2], is, R[rs1]); break;
      case 0x13:
        if (f3 == 1 || f3 == 5)
          std::snprintf(s, sizeof s, "%s %s,%s,0x%x", f3 == 5 && f7 == 0x20 ? "srai" : IA[f3], R[rd], R[rs1], rs2);
        else
          std::snprintf(s, sizeof s, "%s %s,%s,%d", IA[f3], R[rd], R[rs1], ii);
        break;
      case 0x33:
        std::snprintf(s, sizeof s, "%s %s,%s,%s",
                      f7 == 0x20 ? (f3 == 0 ? "sub" : "sra") : RA[f3], R[rd], R[rs1], R[rs2]);
        break;
      case 0x0f: std::snprintf(s, sizeof s, i == 0x0ff0000fu ? "fence iorw,iorw" : "fence 0x%08x", i); break;
      case 0x73: std::snprintf(s, sizeof s, i == 0x00100073u ? "ebreak" : i == 0xc0001073u ? "unimp" : "system 0x%08x", i); break;
      default: std::snprintf(s, sizeof s, "非法 0x%08x", i); break;
    }
    return s;
  }

 private:
  uint32_t fetch(uint32_t a) const { return read_word(a); }
  uint32_t read_word(uint32_t a) const {
    const uint32_t k = (a - kBase) >> 2;
    return k < kWords ? mem[k] : 0;
  }
  void write_word(uint32_t a, uint32_t d, uint8_t m) {
    const uint32_t k = (a - kBase) >> 2;
    if (k >= kWords) return;
    for (int j = 0; j < 4; ++j)
      if (m >> j & 1) mem[k] = (mem[k] & ~(0xffu << 8 * j)) | (d & (0xffu << 8 * j));
  }
};
