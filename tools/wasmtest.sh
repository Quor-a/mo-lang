#!/bin/bash
# wasmtest —— 同一份墨语言源码，原生 x86-64 与 WebAssembly 输出必须一致
#
# 这是本项目**第一份真正的跨环境运行时验证**：
# 此前的内核 / Windows / 安卓目标都只能验证产物结构，不能执行。
set +e
cd "$(dirname "$0")/.."
ROOT=$PWD
W=/tmp/mowtest; rm -rf $W; mkdir -p $W
fail=0
NUM=0

run_case() {
  src=$1; NUM=$((NUM+1))
  b=$(basename "$src" .mo)
  # 原生
  rm -rf $W/n; mkdir -p $W/n; cp $ROOT/lib/*.mo $W/n/ 2>/dev/null; cp "$ROOT/$src" $W/n/test.mo
  ( cd $W/n && timeout 60 $ROOT/bin/moc >/dev/null 2>&1 ) || { echo "  ✗ $b 原生编译失败"; fail=$((fail+1)); return; }
  ( cd $W/n && timeout 20 ./out.elf > $W/n.out 2>&1 ); nrc=$?
  # WASM
  bash $ROOT/tools/wasm.sh "$ROOT/$src" $W/$b.wasm > $W/$b.log 2>&1 || { echo "  ✗ $b WASM 构建失败"; fail=$((fail+1)); return; }
  # 从日志里取"运行输出"段
  sed -n '/--- 运行输出 ---/,/--- 退出码/p' $W/$b.log | grep -v '^  --- ' | grep -v ExperimentalWarning | grep -v trace-warnings | sed 's/^  //' > $W/$b.out
  wrc=$(grep -o '退出码: [0-9]*' $W/$b.log | grep -o '[0-9]*' | tail -1)
  if ! diff -q $W/n.out $W/$b.out >/dev/null 2>&1; then
    echo "  ✗ $b 输出不一致"
    echo "    原生: $(head -3 $W/n.out | tr '\n' '|')"
    echo "    wasm: $(head -3 $W/$b.out | tr '\n' '|')"
    fail=$((fail+1)); return
  fi
  # 退出码**不比对**：实测 node 的 WASI(preview1) 不传播退出码 ——
  # 用一个 `int main(){return 3;}` 的极小 wasm 验证过，node 直接返回 0。
  # 所以这里只比对 stdout，这一点在 docs 里如实说明。
  echo "  ✓ $b（stdout 逐字节一致，原生退出码 $nrc）"
}

echo "wasmtest:"
run_case examples/wasmdemo.mo
if [ $fail -eq 0 ]; then echo "wasmtest: OK（$NUM 个用例，原生与 WASM 输出一致）"; else echo "wasmtest: $fail 项未通过"; exit 1; fi
