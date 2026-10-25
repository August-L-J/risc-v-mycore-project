RISCV_PREFIX ?= riscv64-unknown-elf-
CC      := $(RISCV_PREFIX)gcc
OBJDUMP := $(RISCV_PREFIX)objdump
OBJCOPY := $(RISCV_PREFIX)objcopy
MARCH   := -march=rv32i -mabi=ilp32

# 都可以在命令行上覆盖，不用改这个文件。例如用一份注入了 bug 的 RTL 副本跑，结果放到单独目录：
#   make wave PROG=t2_branch RTL_DIR=/tmp/rtl_bug BUILD=/tmp/build_bug
BUILD   ?= build
RTL_DIR ?= rtl
# 本项目自己装的工具（lz4、riscv-tests……）所在目录。env-riscv.sh 会设置 RISCV_TOOLS；
# 不在干净环境里用 make 时退回这个默认值
RISCV_TOOLS ?= $(HOME)/A_LwxFiles/EngineerTools/Related_ToolChain_4_RISCV_CoreProject

VFLAGS := --cc --exe --build -Wall -Wno-UNUSEDSIGNAL -j 4 -I$(RTL_DIR)

.PHONY: smoke hello clean test-alu test-regfile test-unit test-regfile-xinit test-imm test-decoder test-lsu \
        core progs run test-core lint synth core-wave wave isa isa-progs isa-run isa-wave

# 单元测试：make test-alu / test-regfile / test-imm / test-decoder / test-lsu；make test-unit 全部都跑
test-alu:
	mkdir -p $(BUILD)/alu
	verilator $(VFLAGS) --Mdir $(BUILD)/alu --top-module alu \
	  $(RTL_DIR)/core_pkg.sv $(RTL_DIR)/alu.sv sim/unit/tb_alu.cpp
	$(BUILD)/alu/Valu

test-regfile:
	mkdir -p $(BUILD)/regfile
	verilator $(VFLAGS) --Mdir $(BUILD)/regfile --top-module regfile \
	  $(RTL_DIR)/regfile.sv sim/unit/tb_regfile.cpp
	$(BUILD)/regfile/Vregfile

test-imm:
	mkdir -p $(BUILD)/imm_gen
	verilator $(VFLAGS) --Mdir $(BUILD)/imm_gen --top-module imm_gen \
	  $(RTL_DIR)/core_pkg.sv $(RTL_DIR)/imm_gen.sv sim/unit/tb_imm_gen.cpp
	$(BUILD)/imm_gen/Vimm_gen

test-decoder:
	mkdir -p $(BUILD)/decoder
	verilator $(VFLAGS) --Mdir $(BUILD)/decoder --top-module decoder \
	  $(RTL_DIR)/core_pkg.sv $(RTL_DIR)/decoder.sv sim/unit/tb_decoder.cpp
	$(BUILD)/decoder/Vdecoder

test-lsu:
	mkdir -p $(BUILD)/lsu
	verilator $(VFLAGS) --Mdir $(BUILD)/lsu --top-module lsu \
	  $(RTL_DIR)/lsu.sv sim/unit/tb_lsu.cpp
	$(BUILD)/lsu/Vlsu

test-unit: test-alu test-regfile test-regfile-xinit test-imm test-decoder test-lsu

# 寄存器上电初值随机化：抓“依赖初值为 0”的设计（例如 x0 只靠写时挡住）
test-regfile-xinit:
	mkdir -p $(BUILD)/regfile_xinit
	verilator $(VFLAGS) --x-initial unique --Mdir $(BUILD)/regfile_xinit --top-module regfile \
	  $(RTL_DIR)/regfile.sv sim/unit/tb_regfile.cpp
	$(BUILD)/regfile_xinit/Vregfile +verilator+rand+reset+2 +verilator+seed+20261010

# 代码检查：只做 lint，不生成仿真模型
RTL_SRCS := $(addprefix $(RTL_DIR)/,core_pkg.sv alu.sv regfile.sv imm_gen.sv decoder.sv lsu.sv core_top.sv)
lint:
	for m in alu regfile imm_gen decoder lsu core_top; do \
	  verilator --lint-only -Wall -Wno-UNUSEDSIGNAL -I$(RTL_DIR) --top-module $$m $(RTL_SRCS) || exit 1; \
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
	@if grep -qs 'EngineerTools/verilator-5.052/' $(BUILD)/core/*.d; then \
	  echo "$(BUILD)/core 是工具目录搬家（2026-10-25）之前编译的，里面还记着旧路径，先删掉再编：rm -rf $(BUILD)/core"; exit 1; fi
	mkdir -p $(BUILD)/core
	verilator $(VFLAGS) --Mdir $(BUILD)/core --top-module soc_top \
	  $(SIM_SRCS) sim/core/tb_core.cpp

# ---------------- 波形（L6） ----------------
# make core-wave：编译带 FST 波形的整核模型 build/core_wave/Vsoc_top（单独目录，不影响 make core）
# make wave PROG=t2_branch [TRACE=1] [EXPECT=e]：跑一个程序并生成 build/wave/t2_branch.fst；再用 gtkwave 打开
# FST 压缩要用 lz4：头文件和库装在 RISCV_TOOLS 下，没有写进系统目录
LZ4_DIR ?= $(RISCV_TOOLS)/lz4-1.9.3
WAVE_FLAGS := --trace-fst --trace-structs \
  -CFLAGS -I$(LZ4_DIR)/include -LDFLAGS "-L$(LZ4_DIR)/lib -Wl,-rpath,$(LZ4_DIR)/lib"

core-wave:
	@if grep -qs 'EngineerTools/verilator-5.052/' $(BUILD)/core_wave/*.d; then \
	  echo "$(BUILD)/core_wave 是工具目录搬家（2026-10-25）之前编译的，里面还记着旧路径，先删掉再编：rm -rf $(BUILD)/core_wave"; exit 1; fi
	mkdir -p $(BUILD)/core_wave
	verilator $(VFLAGS) $(WAVE_FLAGS) --Mdir $(BUILD)/core_wave --top-module soc_top \
	  $(SIM_SRCS) sim/core/tb_core.cpp

wave: core-wave progs
	mkdir -p $(BUILD)/wave
	-$(BUILD)/core_wave/Vsoc_top +prog=$(PROG_DIR)/$(PROG).hex +wave=$(BUILD)/wave/$(PROG).fst $(if $(TRACE),+trace) $(if $(EXPECT),+expect_a0=$(EXPECT))
	@echo "波形：$(BUILD)/wave/$(PROG).fst    查看：gtkwave $(BUILD)/wave/$(PROG).fst"

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

# EXPECT=e：顺便检查结束时 a0 等于这个十六进制值（不给就只看是否正常走到 ebreak）
PROG   ?= t1_alu
TRACE  ?=
EXPECT ?=
run: core progs
	$(BUILD)/core/Vsoc_top +prog=$(PROG_DIR)/$(PROG).hex $(if $(TRACE),+trace) $(if $(EXPECT),+expect_a0=$(EXPECT))

# ---------------- 官方测试集 riscv-tests（L7） ----------------
# make isa：编译 rv32ui 的全部测试并跑一遍，汇总 PASS / FAIL
# make isa-run T=rv32ui-p-add [TRACE=1]：只跑一个（调试用）
# 测试源码在 RISCV_TESTS（官方仓库，克隆在 RISCV_TOOLS 下，不改它）；
# 运行环境换成 sw/riscv-tests-env/ 里的最小环境：不用 CSR，结束时 a0 = 0 表示通过
RISCV_TESTS ?= $(RISCV_TOOLS)/riscv-tests
ISA_ENV  := sw/riscv-tests-env
ISA_DIR  := $(BUILD)/isa
# 不在本阶段范围内、暂不跑的两个（原因见 L7 讲义第 6 节）：
#   fence_i：fence.i 属于 Zifencei 扩展，你的译码器按 RV32I 把它当非法指令
#   ma_data：非对齐访存。规范允许硬件不支持、改为触发异常，你的核目前没有异常机制
ISA_SKIP := fence_i ma_data
ISA_ALL  := $(shell sed -n '/rv32ui_sc_tests = /,/^$$/p' $(RISCV_TESTS)/isa/rv32ui/Makefrag 2>/dev/null | grep -v '=' | tr -d '\\')
ISA_TESTS := $(filter-out $(ISA_SKIP),$(ISA_ALL))
ISA_FLAGS := -march=rv32i -mabi=ilp32 -static -mcmodel=medany -nostdlib -nostartfiles \
  -Wl,--build-id=none -Wl,--no-warn-rwx-segments \
  -I$(ISA_ENV) -I$(RISCV_TESTS)/isa/macros/scalar -T$(ISA_ENV)/link.ld

$(ISA_DIR)/rv32ui-p-%.elf: $(RISCV_TESTS)/isa/rv32ui/%.S $(ISA_ENV)/riscv_test.h $(ISA_ENV)/link.ld
	@mkdir -p $(ISA_DIR)
	$(CC) $(ISA_FLAGS) $< -o $@

$(ISA_DIR)/%.hex: $(ISA_DIR)/%.elf
	$(OBJDUMP) -d $< > $(ISA_DIR)/$*.dis
	$(OBJCOPY) -O binary $< $(ISA_DIR)/$*.bin
	python3 sim/core/bin2hex.py $(ISA_DIR)/$*.bin $@

.PRECIOUS: $(ISA_DIR)/%.elf

isa-progs:
	@test -d $(RISCV_TESTS)/isa/rv32ui || { echo "找不到 riscv-tests：$(RISCV_TESTS)（见 L7 讲义第 3 节）"; exit 1; }
	@$(MAKE) --no-print-directory $(addprefix $(ISA_DIR)/rv32ui-p-,$(addsuffix .hex,$(ISA_TESTS)))

isa: core isa-progs
	@bash sim/core/run_isa.sh $(BUILD)/core/Vsoc_top $(ISA_DIR) $(addprefix rv32ui-p-,$(ISA_TESTS))
	@echo "（暂不跑：$(ISA_SKIP)）"

T ?= rv32ui-p-simple
isa-run: core isa-progs
	$(BUILD)/core/Vsoc_top +prog=$(ISA_DIR)/$(T).hex +expect_a0=0 +max=500000 $(if $(TRACE),+trace)

# make isa-wave T=rv32ui-p-blt [TRACE=1]：跑一个 riscv-tests 并生成 $(BUILD)/wave/$(T).fst
# 只编译这一个测试（不像 isa-run 那样先把 40 个都编一遍）；FAIL 时也照样生成波形
isa-wave: core-wave $(ISA_DIR)/$(T).hex
	mkdir -p $(BUILD)/wave
	-$(BUILD)/core_wave/Vsoc_top +prog=$(ISA_DIR)/$(T).hex +wave=$(BUILD)/wave/$(T).fst +expect_a0=0 +max=500000 $(if $(TRACE),+trace)
	@echo "波形：$(BUILD)/wave/$(T).fst    查看：gtkwave $(BUILD)/wave/$(T).fst &"
	@echo "第 n 条指令（trace 最左边的数）在波形里的时刻：5 + 2n（clk 低，信号已稳定）"

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
