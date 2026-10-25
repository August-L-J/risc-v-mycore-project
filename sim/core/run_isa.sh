#!/usr/bin/env bash
# 一键回归：依次运行 build/isa/ 下所有 rv32ui-p-*.hex，汇总 PASS / FAIL
# 用法：sim/core/run_isa.sh 模型可执行文件 hex目录 [测试名 ...]
#   不给测试名就跑目录里全部；失败的测试会把测试号解码出来，方便直接去 .dis 里找
# 返回值：全部通过为 0，否则为 1（make 据此判断）
set -u
SIM="$1"; DIR="$2"; shift 2
if [ $# -gt 0 ]; then
  LIST=("$@")
else
  LIST=()
  for f in "$DIR"/rv32ui-p-*.hex; do LIST+=("$(basename "$f" .hex)"); done
fi

pass=0; fail=0; failed=()
for name in "${LIST[@]}"; do
  hex="$DIR/$name.hex"
  if [ ! -f "$hex" ]; then echo "  ????  $name（找不到 $hex）"; fail=$((fail+1)); failed+=("$name"); continue; fi
  # riscv-tests 的约定（见 sw/riscv-tests-env/riscv_test.h）：通过时 a0 = 0
  out=$("$SIM" +prog="$hex" +expect_a0=0 +max=500000 2>&1 | tail -1)
  if [ "${PIPESTATUS[0]:-1}" = "0" ] && echo "$out" | grep -q -- "-> PASS"; then
    pass=$((pass+1)); printf "  PASS  %s\n" "$name"
  else
    fail=$((fail+1)); failed+=("$name")
    # 取第一个 “a0 = ”（实际值）；后面还有一个 “期望 a0 = ”，贪婪匹配会错拿到它
    a0=$(echo "$out" | grep -o 'a0 = [0-9a-f]\{8\}' | head -1 | cut -d' ' -f3)
    why=$(echo "$out" | sed -n 's/^CORE: \([^，]*\).*/\1/p')
    hint=""
    if [ -n "$a0" ] && [ "$why" = "ebreak" ] && [ $((16#$a0 & 1)) -eq 1 ]; then
      hint="，第 $(( (16#$a0 - 1) / 2 )) 项（test_$(( (16#$a0 - 1) / 2 ))）不对"
    fi
    printf "  FAIL  %-20s %s%s\n" "$name" "${why:-无输出}" "$hint"
  fi
done

echo "riscv-tests rv32ui-p：${pass} 通过，${fail} 失败，共 $((pass+fail)) 个"
if [ $fail -gt 0 ]; then
  echo "失败：${failed[*]}"
  echo "单独看一个：make isa-run T=${failed[0]} TRACE=1"
  exit 1
fi
exit 0
