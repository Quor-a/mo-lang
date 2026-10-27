#!/usr/bin/env bash
# fmathrange —— sin/cos 范围规约误差 vs |x| 的曲线
#
# 🔴 本脚本的判据被**反转过一次**，值得记下来：
#    第一版判据是"误差必须随 |x| 单调增长"，理由是 k·(π/2) 这个乘积
#    本身要舍入，误差 ∝ |x|。实测确实如此（2^21 时 4.9e7 ulp），
#    于是当时把它**写成了"已知限制"**。
#    但那是错的：π/2 用的是"最近双精度值"（53 位全有效），
#    所以 k 乘上去不精确。换成 fdlibm 的**低位清零分裂**后
#    （k·pio2_hi 在 k<2^25 时精确），2^21 的误差从 4.9e7 ulp 降到 1 ulp。
#
#    教训：**"已知限制"是 bug 最好的藏身处**。
#    看到误差随某个参数增长，先问"这是不是能修的"，再决定记不记。
#
# 现在的判据反过来：误差必须在**所有**量级都 ≤2 ulp（平坦）。
# 一旦某个量级冒上去，就说明归约退化成了旧行为 → 红。
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
W=/tmp/mofmathr; rm -rf $W; mkdir -p $W/lib
cp $ROOT/lib/*.mo $W/lib/

cat > $W/test.mo <<'MO'
import "io.mo";
import "fmath.mo";

var S: i64 = 987654321;
fn nexts() -> i64 {
    S = S * 6364136223846793005 + 1442695040888963407;
    return S;
}
# 每个量级 20 个随机相位，共 8 个量级：2^0 .. 2^21
var EXP: [8] i64 = 0;
fn main() -> i64 {
    EXP[0] = 0; EXP[1] = 3; EXP[2] = 6; EXP[3] = 10;
    EXP[4] = 13; EXP[5] = 16; EXP[6] = 19; EXP[7] = 21;
    let i: i64 = 0;
    while i < 8 {
        let j: i64 = 0;
        while j < 20 {
            let s: i64 = nexts();
            let mn: i64 = (s << 4) & 4503599627370495;
            let b: i64 = (1023 << 52) | mn;      # m ∈ [1,2)
            let x: f64 = fm_ldexp(ffrombits(b), EXP[i]);
            print_i64(EXP[i]); print(" ");
            print_i64(fbits(x)); print(" ");
            print_i64(fbits(fm_sin(x))); print(" ");
            print_i64(fbits(fm_cos(x))); print("\n");
            j = j + 1;
        }
        i = i + 1;
    }
    return 0;
}
MO

( cd $W && rm -f out.elf && timeout 900 $ROOT/bin/moc >/dev/null 2>&1 )
if [ ! -f $W/out.elf ]; then echo "fmathrange: ✗ 编译失败"; exit 1; fi
( cd $W && timeout 120 ./out.elf > $W/got.txt 2>&1 )

python3 - $W/got.txt <<'PY'
import sys, struct, math
def bits2f(b): return struct.unpack('<d', struct.pack('<q', b))[0]
def f2bits(v): return struct.unpack('<q', struct.pack('<d', v))[0]
def order(b):
    u = struct.unpack('<Q', struct.pack('<q', b))[0]
    return u if u < (1 << 63) else -(u - (1 << 63))

rows = [l.split() for l in open(sys.argv[1]) if l.strip()]
agg = {}
for e, xb, sb, cb in rows:
    e = int(e); xv = bits2f(int(xb))
    for tag, got, want in (('sin', int(sb), math.sin(xv)), ('cos', int(cb), math.cos(xv))):
        d = abs(order(got) - order(f2bits(want)))
        k = (e, tag)
        w = agg.get(k, (0, 0, 0))
        agg[k] = (max(w[0], d), w[1] + d, w[2] + 1)

LIM = 2
print("|x| 量级       sin 最大ULP   sin 平均    cos 最大ULP   cos 平均")
bad = []
for e in [0, 3, 6, 10, 13, 16, 19, 21]:
    sm, sa, n = agg[(e, 'sin')]; cm, ca, _ = agg[(e, 'cos')]
    print("2^%-2d (%9.0f)  %10d %9.1f   %10d %9.1f"
          % (e, 2.0**e, sm, sa/n, cm, ca/n))
    if max(sm, cm) > LIM: bad.append((e, sm, cm))

print()
if not agg:
    print("✗ 没有任何数据 —— 测试没真正跑起来"); sys.exit(1)
if bad:
    print("✗ 以下量级误差超过 %d ulp（范围规约退化）：" % LIM)
    for e, sm, cm in bad: print("  2^%d: sin %d ulp, cos %d ulp" % (e, sm, cm))
    sys.exit(1)
print("✓ 全部 %d 个量级（2^0 .. 2^21）误差均 ≤ %d ulp —— 归约在各量级都精确"
      % (len(agg) // 2, LIM))
PY
