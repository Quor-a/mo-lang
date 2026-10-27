#!/bin/bash
# diag_android —— 在 ARM64 + qemu 下定位测试失败原因
#
#   bash tools/diag_android.sh
#
# 原理：把每个测试用例用本机 bin/moc 编译，记录产物 md5。
# 与 tools/ref_md5.txt（x86-64 原生环境生成）比对：
#   - md5 相同      → 生成的代码完全一致，问题在**运行时**（栈/brk/argv）
#   - md5 不同      → 编译器链产出了不同字节，问题在**构建**（as 版本）
#   - 编译就失败    → 编译器本身的问题
cd "$(dirname "$0")/.."
OUT=/tmp/mo_diag
rm -rf $OUT; mkdir -p $OUT/lib
cp lib/*.mo $OUT/lib/
echo "=== 逐个编译测试，记录 md5 ==="
: > /tmp/my_md5.txt
# 顺带统计 errors 用例：它们**期望编译失败**。
# 若某个在本机编译成功了，说明诊断行为不一致，也是失败来源。
echo "=== errors 用例（期望编译失败）==="
for f in tests/errors/*.mo; do
  b=$(basename $f)
  cp "$f" $OUT/test.mo
  ( cd $OUT && timeout 60 ../bin/moc >/dev/null 2>&1 )
  if [ -f $OUT/out.elf ]; then echo "  ✗ $b 应报错却编译通过"; rm -f $OUT/out.elf; fi
done
echo
for f in tests/*.mo; do
  b=$(basename $f)
  cp "$f" $OUT/test.mo
  ( cd $OUT && timeout 60 ../bin/moc >/dev/null 2>&1 )
  if [ -f $OUT/out.elf ]; then
    m=$(md5sum $OUT/out.elf | cut -d' ' -f1)
    echo "$b $m" >> /tmp/my_md5.txt
  else
    echo "$b COMPILE_FAIL" >> /tmp/my_md5.txt
  fi
  rm -f $OUT/out.elf
done
echo
echo "=== 与 x86-64 原生参考比对 ==="
if [ -f tools/ref_md5.txt ]; then
  same=0; diff=0; miss=0
  while read b m; do
    r=$(grep "^$b " tools/ref_md5.txt | cut -d' ' -f2)
    if [ -z "$r" ]; then miss=$((miss+1)); echo "  无参考: $b"
    elif [ "$r" = "$m" ]; then same=$((same+1))
    else diff=$((diff+1)); echo "  ✗ 字节不同: $b  (本机=$m 参考=$r)"
    fi
  done < /tmp/my_md5.txt
  echo
  echo "一致: $same   不同: $diff   无参考: $miss"
  echo
  if [ $diff -eq 0 ]; then
    echo "结论：生成的代码与原生环境**完全一致**。"
    echo "      失败不是编译器的问题，而是**运行时环境**差异。"
    echo "      下一步请跑：bash tools/diag_runtime.sh"
  else
    echo "结论：编译器链产出了不同字节 → 问题在构建侧（as/ld 版本）。"
  fi
else
  echo "缺少 tools/ref_md5.txt"
fi
