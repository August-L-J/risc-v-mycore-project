RISCV_PREFIX ?= riscv64-unknown-elf-
CC      := $(RISCV_PREFIX)gcc
OBJDUMP := $(RISCV_PREFIX)objdump
OBJCOPY := $(RISCV_PREFIX)objcopy
MARCH   := -march=rv32i -mabi=ilp32

BUILD := build

VFLAGS := --cc --exe --build -Wall -Wno-UNUSEDSIGNAL -j 4 -Irtl

.PHONY: smoke hello clean test-alu test-regfile test-unit test-regfile-xinit test-imm test-decoder test-lsu \
        core progs run test-core lint synth

# 单元测试：make test-alu / test-regfile / test-imm / test-decoder / test-lsu；make test-unit 全部都跑
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

test-imm:
	mkdir -p $(BUILD)/imm_gen
	verilator $(VFLAGS) --Mdir $(BUILD)/imm_gen --top-module imm_gen \
	  rtl/core_pkg.sv rtl/imm_gen.sv sim/unit/tb_imm_gen.cpp
	$(BUILD)/imm_gen/Vimm_gen

test-decoder:
	mkdir -p $(BUILD)/decoder
	verilator $(VFLAGS) --Mdir $(BUILD)/decoder --top-module decoder \
	  rtl/core_pkg.sv rtl/decoder.sv sim/unit/tb_decoder.cpp
	$(BUILD)/decoder/Vdecoder

test-lsu:
	mkdir -p $(BUILD)/lsu
	verilator $(VFLAGS) --Mdir $(BUILD)/lsu --top-module lsu \
	  rtl/lsu.sv sim/unit/tb_lsu.cpp
	$(BUILD)/lsu/Vlsu

test-unit: test-alu test-regfile test-regfile-xinit test-imm test-decoder test-lsu

# 寄存器上电初值随机化：抓“依赖初值为 0”的设计（例如 x0 只靠写时挡住）
test-regfile-xinit:
	mkdir -p $(BUILD)/regfile_xinit
	verilator $(VFLAGS) --x-initial unique --Mdir $(BUILD)/regfile_xinit --top-module regfile \
	  rtl/regfile.sv sim/unit/tb_regfile.cpp
	$(BUILD)/regfile_xinit/Vregfile +verilator+rand+reset+2 +verilator+seed+20261010

# 代码检查：只做 lint，不生成仿真模型
RTL_SRCS := rtl/core_pkg.sv rtl/alu.sv rtl/regfile.sv rtl/imm_gen.sv rtl/decoder.sv rtl/lsu.sv rtl/core_top.sv
lint:
	for m in alu regfile imm_gen decoder lsu core_top; do \
	  verilator --lint-only -Wall -Wno-UNUSEDSIGNAL -Irtl --top-module $$m $(RTL_SRCS) || exit 1; \
	done
	@echo "lint: 0 warnings"

# 开源综合（Yosys + slang 前端）：看面积（单元数）和逻辑深度。SYNTH_TOP=alu / regfile / imm_gen / decoder / lsu / core_top
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

# ---------------- 整核仿真（L5） ----------------
# make core：编译整核仿真模型 build/core/Vsoc_top（你的 core_top + 仿真存储器）
# make progs：把 sw/tests/*.S 和 sw/hello 编译成 build/progs/*.hex
# make run PROG=t1_alu [TRACE=1]：跑一个程序；TRACE=1 打印每条指令
# make test-core：跑全部程序并检查结果
SIM_SRCS := $(RTL_SRCS) sim/core/mem.sv sim/core/soc_top.sv
PROG_DIR := $(BUILD)/progs
TESTS    := t1_alu t2_branch t3_mem
LDS      := sw/hello/link.ld
SW_FLAGS := $(MARCH) -nostdlib -ffreestanding -Wl,--build-id=none -Wl,--no-warn-rwx-segments -T $(LDS)

core:
	mkdir -p $(BUILD)/core
	verilator $(VFLAGS) --Mdir $(BUILD)/core --top-module soc_top \
	  $(SIM_SRCS) sim/core/tb_core.cpp

$(PROG_DIR)/%.elf: sw/tests/%.S $(LDS)
	mkdir -p $(PROG_DIR)
	$(CC) $(SW_FLAGS) -Wl,--section-start=.buf=0x80001000 $< -o $@

$(PROG_DIR)/hello.elf: sw/common/start_sim.S sw/hello/main.c $(LDS)
	mkdir -p $(PROG_DIR)
	$(CC) $(SW_FLAGS) -O2 sw/common/start_sim.S sw/hello/main.c -o $@

$(PROG_DIR)/sum.elf: sw/common/start_sim.S sw/sum/main.c $(LDS)
	mkdir -p $(PROG_DIR)
	$(CC) $(SW_FLAGS) -O2 sw/common/start_sim.S sw/sum/main.c -o $@

# 保留 .elf 等中间文件，方便你用 objdump 自己看
.PRECIOUS: $(PROG_DIR)/%.elf

$(PROG_DIR)/%.hex: $(PROG_DIR)/%.elf
	$(OBJDUMP) -d $< > $(PROG_DIR)/$*.dis
	$(OBJCOPY) -O binary $< $(PROG_DIR)/$*.bin
	python3 sim/core/bin2hex.py $(PROG_DIR)/$*.bin $@

progs: $(addprefix $(PROG_DIR)/,$(addsuffix .hex,$(TESTS) hello sum))

PROG  ?= t1_alu
TRACE ?=
run: core progs
	$(BUILD)/core/Vsoc_top +prog=$(PROG_DIR)/$(PROG).hex $(if $(TRACE),+trace)

# 每个程序的预期结果：a0 的值，以及（t3_mem）存储器里三个字的值
# hello 在 -O2 下被编译器算成了常数 55，循环不在核上跑；sum 的 n 来自 volatile，循环真的执行 100 次
test-core: core progs
	$(BUILD)/core/Vsoc_top +prog=$(PROG_DIR)/t1_alu.hex    +expect_a0=2a
	$(BUILD)/core/Vsoc_top +prog=$(PROG_DIR)/t2_branch.hex +expect_a0=e
	$(BUILD)/core/Vsoc_top +prog=$(PROG_DIR)/t3_mem.hex    +expect_a0=0 \
	  +expect_mem=80001000:8765dd21 +expect_mem=80001004:ccdd0000 +expect_mem=80001008:11223344
	$(BUILD)/core/Vsoc_top +prog=$(PROG_DIR)/hello.hex     +expect_a0=0
	$(BUILD)/core/Vsoc_top +prog=$(PROG_DIR)/sum.hex       +expect_a0=0

clean:
	rm -rf $(BUILD)
