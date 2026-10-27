#!/usr/bin/env bash
# fmathtest —— fmath 的**逐点 ULP 交叉验证**
#
# 为什么不能用"跑通就算过"：数学函数的错误几乎全是**静默**的 ——
# 漏一项级数、系数写错一位、常量被截断，结果都"看起来是个数"。
# 实测中 exp 漏写 1/10! 一项，exp(1) 只差 1.9e-12，肉眼完全看不出。
#
# 做法：墨语言与 Python（C library，正确舍入）算同一批输入，
# 误差用 **ULP**（位模式在 total order 下的整数距离）衡量，不用相对误差
# —— 后者在接近 0 处会失真、跨 0 时甚至无定义。
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
W=/tmp/mofmath; rm -rf $W; mkdir -p $W/lib
cp $ROOT/lib/*.mo $W/lib/

# 输入生成：LCG（两边各实现一份，序列必须完全一致）
#   s = s·6364136223846793005 + 1442695040888963407   (mod 2^64)
#   ex  = 1023 + ((s>>16) & 31) - 16     指数 ∈ [1007, 1038] → x ∈ [2^-16, 2^15]
#   mn  = (s<<4) & (2^52-1)              尾数
#   sg  = (s>>60) & 1                    符号
# ⚠️ 取位要用**高位**：低位在模 2^64 的 LCG 上周期极短（1.111 踩过：
#    取 h&1 时序列必然逐位交替，256 个样本只有 2 种不同输入）。
cat > $W/test.mo <<'MO'
import "io.mo";
import "fmath.mo";

var S: i64 = 88172645463325252;
var NPT: i64 = 200;

fn nexts() -> i64 {
    S = S * 6364136223846793005 + 1442695040888963407;
    return S;
}
fn mkx(sg: i64, ex: i64, mn: i64) -> f64 {
    let b: i64 = (ex << 52) | mn;
    if sg == 1 { b = b | (0 - 9223372036854775807 - 1); }
    return ffrombits(b);
}
fn emit(name: i64, x: f64, y: f64) -> i64 {
    print(name); print(" ");
    print_i64(fbits(x)); print(" ");
    print_i64(fbits(y)); print("\n");
    return 0;
}

fn main() -> i64 {
    let i: i64 = 0;
    while i < NPT {
        let s: i64 = nexts();
        let sg: i64 = (s >> 60) & 1;
        let ex: i64 = 1023 + ((s >> 16) & 31) - 16;
        let mn: i64 = (s << 4) & 4503599627370495;
        let x: f64 = mkx(sg, ex, mn);
        let y: f64 = fm_fabs(x);
        emit("sqrt", y, fm_sqrt(y));
        emit("exp",  x, fm_exp(x));
        emit("log",  y, fm_log(y));
        emit("log2", y, fm_log2(y));
        emit("log10", y, fm_log10(y));
        emit("floor", x, fm_floor(x));
        emit("ceil",  x, fm_ceil(x));
        emit("round", x, fm_round(x));
        emit("hypot", x, fm_hypot(x, y));
        # sin/cos 用**另一组**输入：范围规约误差 ∝ |x|（见 fmathrange.sh），
        # 拿宽范围输入测会淹没真正的算法误差。这里只取 |x| ≤ 8。
        let s2: i64 = nexts();
        let sg2: i64 = (s2 >> 60) & 1;
        let ex2: i64 = 1023 + ((s2 >> 16) & 7) - 4;
        let mn2: i64 = (s2 << 4) & 4503599627370495;
        let z: f64 = mkx(sg2, ex2, mn2);
        emit("sin", z, fm_sin(z));
        emit("cos", z, fm_cos(z));
        i = i + 1;
    }
    return 0;
}
MO

( cd $W && rm -f out.elf && timeout 900 $ROOT/bin/moc >/dev/null 2>&1 )
if [ ! -f $W/out.elf ]; then
    echo "fmathtest: ✗ 编译失败"; ( cd $W && timeout 900 $ROOT/bin/moc 2>&1 | tail -5 ); exit 1
fi
( cd $W && timeout 120 ./out.elf > $W/got.txt 2>&1 )

python3 - $W/got.txt <<'PY'
import sys, struct, math

M = 1 << 64
def i64(x):
    x &= M - 1
    return x - M if x >= (1 << 63) else x
def bits2f(b): return struct.unpack('<d', struct.pack('<q', b))[0]
def f2bits(v): return struct.unpack('<q', struct.pack('<d', v))[0]
def order(b):
    u = struct.unpack('<Q', struct.pack('<q', b))[0]
    return u if u < (1 << 63) else -(u - (1 << 63))

S = 88172645463325252
NPT = 200
def nexts():
    global S
    S = i64(S * 6364136223846793005 + 1442695040888963407)
    return S
def mkx(sg, ex, mn):
    b = (ex << 52) | mn
    if sg: b = i64(b | (1 << 63))
    return bits2f(b)

F = {'sqrt': math.sqrt, 'exp': math.exp, 'log': math.log, 'sin': math.sin,
     'cos': math.cos, 'log2': math.log2, 'log10': math.log10,
     'floor': math.floor, 'ceil': math.ceil, 'round': lambda v: float(round(v)),
     'hypot': lambda v: math.hypot(v, abs(v))}
# log10 是 log 的派生：log 的 1 ulp + 1/ln10 的表示误差 + 乘法舍入，
# 实测 3 ulp。这里按函数分别给阈值，而不是统一 2 —— 统一阈值会逼着
# 把"合理的派生误差"伪装成通过。
LIM = {'log10': 4}

# 先按测试点顺序重建输入，再按名字匹配
errs = {}
bad = {}
n = 0
lines = [l.split() for l in open(sys.argv[1]) if l.strip()]
by_name = {}
for nm, xb, yb in lines:
    by_name.setdefault(nm, []).append((int(xb), int(yb)))

for i in range(NPT):
    s = nexts()
    sg = (s >> 60) & 1
    ex = 1023 + ((s >> 16) & 31) - 16
    mn = (s << 4) & ((1 << 52) - 1)
    x = mkx(sg, ex, mn)
    y = abs(x)

for nm, pairs in by_name.items():
    fn = F[nm]
    worst = 0; worstx = None; cnt = 0; tot = 0
    for xb, yb in pairs:
        xv = bits2f(xb)
        try:
            wv = fn(xv)
        except (ValueError, OverflowError):
            continue
        if isinstance(wv, int): wv = float(wv)
        if math.isnan(wv) or math.isinf(wv): continue
        d = abs(order(yb) - order(f2bits(wv)))
        tot += d; cnt += 1
        if d > worst: worst, worstx = d, xv
    errs[nm] = (worst, tot / max(cnt, 1), cnt)
    if worst > LIM.get(nm, 2): bad[nm] = (worst, worstx)

# 守卫：输出太少或函数缺失时必须**红着失败**，不能靠"没有超阈值"蒙混过关。
# 否则程序只打印三行也会"全部通过" —— 这正是本项目反复出现的静默少报模式。
WANT = ['sqrt','exp','log','log2','log10','floor','ceil','round','hypot','sin','cos']
missing = [n for n in WANT if n not in by_name]
if missing:
    print("✗ 以下函数没有输出：%s" % ", ".join(missing)); sys.exit(1)
if len(lines) < 2000:
    print("✗ 输出只有 %d 行（应 ≥2000）—— 测试没真正跑起来" % len(lines)); sys.exit(1)

fail = 0
print("函数      最大ULP   平均ULP   点数   阈值")
for nm in sorted(errs):
    w, a, c = errs[nm]
    lim = LIM.get(nm, 2)
    # 🔴 判失败必须与判"列入超阈值清单"用**同一个** LIM。
    #    第一版这里写死 2，于是 log10 的 3 ulp 被判失败（LIM=4 本该放过），
    #    且 bad 里查不到它 —— 打印"超阈值的函数："后面**一个都没有**，
    #    退出码却是 1。这是校验脚本自己的静默失败：报错但说不出报的是谁。
    flag = "  ✗" if w > lim else "   "
    print("%-8s %8d %9.2f %6d %6d%s" % (nm, w, a, c, lim, flag))
    if w > lim: fail += 1

if fail:
    print("\n超阈值的函数：")
    for nm, (w, x) in bad.items(): print("  %s: %d ulp @ x=%r" % (nm, w, x))
    sys.exit(1)
print("\nfmathtest: OK（%d 个点，全部在各自阈值内）" % (len(lines)))
PY
