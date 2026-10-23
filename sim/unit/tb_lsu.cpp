// 访存单元单元测试：store 的写数据与字节掩码、load 的字节选择与扩展，与参考模型逐个对拍
#include <cstdint>
#include <cstdio>
#include <memory>
#include <random>
#include "Vlsu.h"
#include "verilated.h"

static const char* kName[8] = {"lb/sb", "lh/sh", "lw/sw", "?", "lbu", "lhu", "?", "?"};

// 参考模型：按规范的小端定义直接写，不用位拼接
struct Ref { uint32_t addr, wdata, wmask, load; };
static Ref ref(uint32_t addr, uint32_t size, bool we, uint32_t sdata, uint32_t rdata) {
  Ref r{};
  r.addr = addr & ~3u;
  const unsigned off = addr & 3;
  if (we) {
    if (size == 0) { r.wmask = 1u << off;          r.wdata = (sdata & 0xff) << (8 * off); }
    if (size == 1) { r.wmask = 3u << off;          r.wdata = (sdata & 0xffff) << (8 * off); }
    if (size == 2) { r.wmask = 0xf;                r.wdata = sdata; }
  }
  const uint32_t byte = (rdata >> (8 * off)) & 0xff;
  const uint32_t half = (rdata >> (8 * off)) & 0xffff;
  switch (size) {
    case 0: r.load = (uint32_t)(int32_t)(int8_t)byte; break;
    case 1: r.load = (uint32_t)(int32_t)(int16_t)half; break;
    case 2: r.load = rdata; break;
    case 4: r.load = byte; break;
    case 5: r.load = half; break;
  }
  return r;
}

int main(int argc, char** argv) {
  auto ctx = std::make_unique<VerilatedContext>();
  ctx->commandArgs(argc, argv);
  auto dut = std::make_unique<Vlsu>(ctx.get());
  long total = 0, fails = 0;

  auto check = [&](uint32_t addr, uint32_t size, bool we, uint32_t sdata, uint32_t rdata) {
    dut->addr = addr; dut->mem_size = size; dut->mem_we = we; dut->store_data = sdata; dut->dmem_rdata = rdata;
    dut->eval();
    const Ref w = ref(addr, size, we, sdata, rdata);
    ++total;
    const char* what = nullptr; uint32_t got = 0, want = 0;
    if (dut->dmem_addr != w.addr) { what = "dmem_addr"; got = dut->dmem_addr; want = w.addr; }
    else if (we && dut->dmem_wmask != w.wmask) { what = "dmem_wmask"; got = dut->dmem_wmask; want = w.wmask; }
    else if (!we && dut->dmem_wmask != 0) { what = "dmem_wmask（不是 store 时必须为 0）"; got = dut->dmem_wmask; want = 0; }
    else if (we) {
      // 只比较被写的那几个字节，其余字节写什么都无所谓（掩码为 0 的字节不会写进存储器）
      uint32_t m = 0;
      for (int i = 0; i < 4; ++i) if (w.wmask >> i & 1) m |= 0xffu << (8 * i);
      if ((dut->dmem_wdata & m) != (w.wdata & m)) { what = "dmem_wdata（被写的字节）"; got = dut->dmem_wdata & m; want = w.wdata & m; }
    } else if (dut->load_data != w.load) { what = "load_data"; got = dut->load_data; want = w.load; }
    if (what && ++fails <= 12)
      std::printf("  FAIL %-5s %s addr=0x%08x off=%u  %s  got 0x%08x  want 0x%08x\n", kName[size],
                  we ? "store" : "load ", addr, addr & 3, what, got, want);
  };

  // 定向：每种宽度 × 每种合法偏移，存储器内容固定为 0x87654321（小端字节 21 43 65 87）
  const uint32_t word = 0x87654321;
  for (uint32_t size : {0u, 1u, 2u, 4u, 5u})
    for (uint32_t off = 0; off < 4; ++off) {
      if ((size == 1 || size == 5) && (off & 1)) continue;  // 半字要 2 字节对齐
      if (size == 2 && off) continue;                         // 字要 4 字节对齐
      check(0x80000100 + off, size, false, 0, word);
      if (size <= 2) check(0x80000100 + off, size, true, 0xaabbccdd, word);
    }

  // 随机：合法（对齐）的访问
  std::mt19937 rng(20261015);
  const uint32_t sizes[] = {0, 1, 2, 4, 5};
  for (int i = 0; i < 200000; ++i) {
    const uint32_t size = sizes[rng() % 5];
    uint32_t addr = rng();
    if (size == 1 || size == 5) addr &= ~1u;
    if (size == 2) addr &= ~3u;
    const bool we = size <= 2 && (rng() & 1);
    check(addr, size, we, rng(), rng());
  }

  dut->final();
  std::printf("LSU: %ld cases, %ld failed -> %s\n", total, fails, fails ? "FAIL" : "PASS");
  return fails ? 1 : 0;
}
