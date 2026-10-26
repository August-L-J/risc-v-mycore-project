#!/usr/bin/env bash
# DiffTest 批量回归：对每个 hex 跑一次 DiffTest 模型，汇总通过 / 失败
# 用法：sim/difftest/run_diff.sh 模型可执行文件 a.hex b.hex ...
# 返回值：全部通过为 0，否则为 1
set -u
SIM="$1"; shift
pass=0; fail=0; failed=()
for hex in "$@"; do
  name=$(basename "$hex" .hex)
  out=$("$SIM" +prog="$hex" 2>&1)
  if [ $? -eq 0 ]; then
    pass=$((pass+1)); printf "  PASS  %-22s %s\n" "$name" "$(echo "$out" | tail -1 | grep -o '比对了 [0-9]* 条指令')"
  else
    fail=$((fail+1)); failed+=("$name")
    printf "  FAIL  %-22s %s\n" "$name" "$(echo "$out" | grep -m1 -E 'DIFFTEST: 第|DIFFTEST: .*FAIL' | sed 's/^DIFFTEST: //')"
  fi
done
echo "DiffTest：${pass} 通过，${fail} 失败，共 $((pass+fail)) 个程序"
if [ $fail -gt 0 ]; then
  echo "失败：${failed[*]}"
  echo "单独看一个：make diff PROG=名字（自写程序）或 make diff-isa T=名字（riscv-tests），加 ITRACE=1 看每条指令"
  exit 1
fi
exit 0
