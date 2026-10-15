RISCV_PREFIX ?= riscv64-unknown-elf-
CC      := $(RISCV_PREFIX)gcc
OBJDUMP := $(RISCV_PREFIX)objdump
OBJCOPY := $(RISCV_PREFIX)objcopy
MARCH   := -march=rv32i -mabi=ilp32

BUILD := build

VFLAGS := --cc --exe --build -Wall -Wno-UNUSEDSIGNAL -j 4 -Irtl

.PHONY: smoke hello clean test-alu test-regfile test-unit test-regfile-xinit lint synth

# 单元测试：make test-alu / make test-regfile / make test-unit（ALU、寄存器堆、随机初值三个都跑）
test-alu:
	mkdir -p $(BUILD)/alu
	verilator $(VFLAGS) --Mdir $(BUILD)/alu --top-module alu \
	  rtl/core_pkg.sv rtl/alu.sv sim/unit/tb_alu.cpp
	$(BUILD)/alu/Valu

test-regfile:
	mkdir -p $(BUILD)/regfile
	verilator $(VFLAGS) --Mdir $(BUILD)/regfile --top-module regfile \
	  rtl/regfile.sv sim/unit/tb_regfile.cpp
	$(BUILD)/regfile/Vregfile

test-unit: test-alu test-regfile test-regfile-xinit

# 寄存器上电初值随机化：抓“依赖初值为 0”的设计（例如 x0 只靠写时挡住）
test-regfile-xinit:
	mkdir -p $(BUILD)/regfile_xinit
	verilator $(VFLAGS) --x-initial unique --Mdir $(BUILD)/regfile_xinit --top-module regfile \
	  rtl/regfile.sv sim/unit/tb_regfile.cpp
	$(BUILD)/regfile_xinit/Vregfile +verilator+rand+reset+2 +verilator+seed+20261010

# 代码检查：只做 lint，不生成仿真模型
RTL_SRCS := rtl/core_pkg.sv rtl/alu.sv rtl/regfile.sv
lint:
	for m in alu regfile; do \
	  verilator --lint-only -Wall -Wno-UNUSEDSIGNAL -Irtl --top-module $$m $(RTL_SRCS) || exit 1; \
	done
	@echo "lint: 0 warnings"

# 开源综合（Yosys + slang 前端）：看面积（单元数）和逻辑深度。SYNTH_TOP=alu 或 regfile
YOSYS ?= yowasp-yosys
SYNTH_TOP ?= alu
synth:
	$(YOSYS) -q -p "read_slang -j 1 $(RTL_SRCS) --top $(SYNTH_TOP); synth -top $(SYNTH_TOP) -noabc; tee -o $(BUILD)/synth_$(SYNTH_TOP).txt stat; tee -a $(BUILD)/synth_$(SYNTH_TOP).txt ltp -noff"
	@grep -E "cells$$|DFF|Longest" $(BUILD)/synth_$(SYNTH_TOP).txt

smoke:
	verilator --cc --exe --build --trace -Wall -j 4 \
	  --Mdir $(BUILD)/smoke --top-module counter \
	  sim/smoke/counter.sv sim/smoke/tb_counter.cpp
	cd $(BUILD)/smoke && ./Vcounter

hello:
	mkdir -p $(BUILD)/hello
	$(CC) $(MARCH) -O2 -nostdlib -ffreestanding -Wl,--build-id=none -T sw/hello/link.ld \
	  sw/hello/start.S sw/hello/main.c -o $(BUILD)/hello/hello.elf
	$(OBJDUMP) -d $(BUILD)/hello/hello.elf > $(BUILD)/hello/hello.dis
	$(OBJCOPY) -O binary $(BUILD)/hello/hello.elf $(BUILD)/hello/hello.bin
	@echo "entry:" $$(grep -m1 '<_start>:' $(BUILD)/hello/hello.dis) \
	  " instructions:" $$(grep -cP '^ *[0-9a-f]+:\t' $(BUILD)/hello/hello.dis)

clean:
	rm -rf $(BUILD)
