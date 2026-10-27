#!/usr/bin/env bash
# f64test —— f64 的**跨实现输出比对**
#
# 为什么单独做：单元测试（tests/88_f64.mo）只能证明"能算"。
# 而浮点最容易错的是**格式化**（截断 vs 四舍五入、负数符号），
# 这类错误单元测试很难覆盖 —— 它是"看起来差不多"的错。
#
# 做法：墨语言 print_f64 的输出与 Python 的 %.6f 逐行比对。
# 两个**独立实现**给出相同结果，才说明真的对。
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
W=/tmp/mof64; rm -rf $W; mkdir -p $W/lib
cp $ROOT/lib/*.mo $W/lib/

cat > $W/test.mo <<'MO'
import "io.mo";
fn main() -> i64 {
    print_f64(1.5 + 2.25); print("\n");
    print_f64(3.0 / 2.0);  print("\n");
    print_f64(1.0 / 3.0);  print("\n");
    print_f64(0.0 - 2.5);  print("\n");
    print_f64(100.0);      print("\n");
    print_f64(3.14159);    print("\n");
    print_f64(2.0 * 3.0);  print("\n");
    print_f64(1.0 + 2);    print("\n");
    print_f64(9.0 / 4.0);  print("\n");
    print_f64(0.1 + 0.2);  print("\n");
    return 0;
}
MO

( cd $W && rm -f out.elf && timeout 600 $ROOT/bin/moc >/dev/null 2>&1 )
if [ ! -f $W/out.elf ]; then echo "f64test: ✗ 编译失败"; exit 1; fi
( cd $W && timeout 60 ./out.elf > $W/got.txt 2>&1 )

python3 - > $W/want.txt <<'PY'
for v in [3.75, 1.5, 1/3, -2.5, 100.0, 3.14159, 6.0, 3.0, 2.25, 0.1+0.2]:
    print("%.6f" % v)
PY

fail=0
if diff -q $W/want.txt $W/got.txt >/dev/null 2>&1; then
    echo "  ✓ print_f64 输出 == Python %.6f（10 项逐行一致）"
else
    echo "  ✗ 与 Python %.6f 不一致："
    paste $W/want.txt $W/got.txt | head -12
    fail=$((fail+1))
fi

# 算术与比较：走 tests/88
cp $ROOT/tests/88_f64.mo $W/test.mo
( cd $W && rm -f out.elf && timeout 600 $ROOT/bin/moc >/dev/null 2>&1 )
if [ ! -f $W/out.elf ]; then echo "  ✗ 88_f64 编译失败"; fail=$((fail+1)); else
    O=$( cd $W && timeout 60 ./out.elf 2>&1 )
    if echo "$O" | grep -q "FAIL"; then echo "  ✗ 88_f64:"; echo "$O" | head -6; fail=$((fail+1));
    else echo "  ✓ 88_f64 全部断言通过"; fi
fi

if [ $fail -eq 0 ]; then echo "f64test: OK（墨语言能算浮点了）"; exit 0; fi
echo "f64test: FAILED（$fail 项）"; exit 1
