#include <cstdio>
#include <memory>
#include "Vcounter.h"
#include "verilated.h"
#include "verilated_vcd_c.h"

int main(int argc, char** argv) {
    auto ctx = std::make_unique<VerilatedContext>();
    ctx->commandArgs(argc, argv);
    ctx->traceEverOn(true);
    auto dut = std::make_unique<Vcounter>(ctx.get());
    auto vcd = std::make_unique<VerilatedVcdC>();
    dut->trace(vcd.get(), 99);
    vcd->open("counter.vcd");

    dut->rst_n = 0;
    for (int cycle = 0; cycle < 20; ++cycle) {
        if (cycle == 2) dut->rst_n = 1;
        dut->clk = 0; dut->eval(); vcd->dump(ctx->time()); ctx->timeInc(5);
        dut->clk = 1; dut->eval(); vcd->dump(ctx->time()); ctx->timeInc(5);
    }
    vcd->close();

    const int expect = 18;
    std::printf("count = %d (expect %d) -> %s\n", dut->count, expect,
                dut->count == expect ? "PASS" : "FAIL");
    return dut->count == expect ? 0 : 1;
}
