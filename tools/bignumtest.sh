#!/bin/bash
# bignumtest —— 用 Python 当"标准答案"，逐字节比对墨语言的大数计算
#
#   bash tools/bignumtest.sh
#
# 为什么这样做：任意精度算术最容易"看起来对"——
# 打印出一长串数字，人眼根本看不出第 200 位错没错。
# Python 的 int 是任意精度的，天然就是标准答案。
# 逐字节 diff 能抓出任何一位的偏差，比人工抽查可靠得多。
set +e
cd "$(dirname "$0")/.."
ROOT=$PWD
W=/tmp/mobig
rm -rf $W; mkdir -p $W/lib
cp lib/*.mo $W/lib/
cp examples/bignum.mo $W/test.mo
( cd $W && "$ROOT/bin/moc" >/dev/null 2>&1 )
[ -x $W/out.elf ] || { echo "编译失败"; exit 1; }
( cd $W && timeout 300 ./out.elf > got.txt 2>&1 )

# ---- Python 生成期望输出（格式必须与 bignum.mo 逐字一致）----
python3 - > $W/want.txt <<'PY'
import math
p = 2 ** 1000
print("2^1000 = %d" % p)
print("digits(2^1000) = %d" % len(str(p)))
print("digitsum(2^1000) = %d" % sum(int(c) for c in str(p)))
f = math.factorial(100)
print("100! = %d" % f)
print("digits(100!) = %d" % len(str(f)))
def fib(n):
    a, b = 0, 1
    for _ in range(n):
        a, b = b, a + b
    return a
fb = fib(500)
print("fib(500) = %d" % fb)
print("digits(fib(500)) = %d" % len(str(fb)))
# Python 的 // 与 % 就是向下取整语义
print("(-7) // 3 = %d" % ((-7) // 3))
print("(-7) %% 3 = %d" % ((-7) % 3))
print("7 // (-3) = %d" % (7 // (-3)))
print("7 %% (-3) = %d" % (7 % (-3)))
print("gcd(12345678901234567890, 9876543210) = %d" % math.gcd(12345678901234567890, 9876543210))
print("pow(2, 1000, 1009) = %d" % pow(2, 1000, 1009))
s = math.isqrt(p)
print("isqrt(2^1000) = %d" % s)
print("isqrt(2^1000)^2 <= 2^1000 ? %s" % ("yes" if s * s <= p else "no"))
x = 99999999999999999999999999
y = 88888888888888888888888888
print("99999999999999999999999999 * 88888888888888888888888888 = %d" % (x * y))
PY

echo "bignumtest:"
if diff -u $W/want.txt $W/got.txt > $W/diff.txt 2>&1; then
  # 顺带核对几个数学事实
  n=$(wc -l < $W/got.txt)
  echo "  ✓ 与 Python 逐字节一致（$n 行输出）"
  grep -q 'digitsum(2^1000) = 1366' $W/got.txt \
    && echo "  ✓ 2^1000 数字和 = 1366（Project Euler 16 的答案）" \
    || { echo "  ✗ 数字和不对"; exit 1; }
  grep -q 'digits(2^1000) = 302' $W/got.txt \
    && echo "  ✓ 2^1000 位数 = 302（i64 装不下，证明是真任意精度）" \
    || { echo "  ✗ 位数不对"; exit 1; }
  echo "bignumtest: OK（全部通过）"
else
  echo "  ✗ 与 Python 不一致："
  head -20 $W/diff.txt
  exit 1
fi
