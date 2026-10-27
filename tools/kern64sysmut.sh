#!/bin/bash
# kern64sysmut.sh —— 证明 kern64systest 的断言**不是空转**
#
# 每个变异都改一处"看起来无害"的实现，然后重跑端到端测试：
# 只要断言真的盯着那条因果链，就必须变红。
#
# 备份放在 build/ 下而不是 /tmp —— /tmp 会被回收（1.128 记过的坑），
# 收尾时**保留备份不删**，并且开工前先自愈（源码可能被上一轮中断留在
# 变异态）。这是本项目第三次在"验证脚本自身的还原"上栽跟头后的写法。
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
SRC=examples/kern64sys.mo
RUN=tools/kern64run.py
BAKD=$ROOT/build/kern64sysmut
mkdir -p "$BAKD"

cp "$SRC" "$BAKD/src.orig"
cp "$RUN" "$BAKD/run.orig"

restore() {
    cp "$BAKD/src.orig" "$SRC"
    cp "$BAKD/run.orig" "$RUN"
}
heal() {
    # 开工前自愈：若源码/工具停在变异态（上一轮被强杀），先还原
    if ! grep -q 'while done == 0 {' "$SRC"; then
        echo "HEAL: 源码处于变异态，已还原"; cp "$BAKD/src.orig" "$SRC"
    fi
    if grep -q 'prime()  # 预置' "$RUN"; then
        echo "HEAL: 模拟器处于变异态，已还原"; cp "$BAKD/run.orig" "$RUN"
    fi
}
trap 'restore; echo "（已还原）"' EXIT INT TERM

pass=0
fail=0
report() { # 名称 期望捕获
    local n=$1 want=$2
    local got
    got=$(bash tools/kern64systest.sh 2>&1 | tail -1)
    local nf
    nf=$(echo "$got" | sed -n 's/.*\/ \([0-9]*\) 失败/\1/p')
    if [ "${nf:-0}" -gt 0 ] && [ "$want" = "捕获" ]; then
        pass=$((pass+1)); echo "✅ $n 被捕获（$got）"
    elif [ "${nf:-0}" -eq 0 ] && [ "$want" = "未捕获" ]; then
        pass=$((pass+1)); echo "✅ $n 如预期未捕获"
    else
        fail=$((fail+1)); echo "❌ $n 期望[$want] 实际[$got]"
    fi
    restore
}

apply_src() { # 旧串 新串
    python3 - "$SRC" "$1" "$2" <<'PY'
import sys
p, a, b = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(p).read()
if a not in s:
    sys.stderr.write("ANCHOR MISS: %r\n" % a[:60]); sys.exit(3)
open(p, 'w').write(s.replace(a, b, 1))
PY
}

heal

echo "=== 基线 ==="
BASE=$(bash tools/kern64systest.sh 2>&1 | tail -1)
echo "$BASE"
case "$BASE" in *"0 失败"*) ;; *) echo "基线就没通过，后续结论无效"; exit 1;; esac

# M1 —— next_tok 回到最初的错法（循环条件 TPOS<n、推进却在 done 块内）
#      取完 token 后还有剩余字符时 TPOS 卡住 → 死循环 → 无声卡死
echo "=== M1 next_tok 游标推进进错块（死循环） ==="
python3 - "$SRC" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
old = """    while done == 0 {
        if TPOS >= n {
            done = 1;
        } else {
            c = load8(&LINE + TPOS);
            TPOS = TPOS + 1;
            if c == 32 {
                if i > 0 {
                    done = 1;
                }
            } else {
                if i < 15 {
                    store8(&TOK + i, c);
                    i = i + 1;
                }
            }
        }
    }"""
# 回到最初的错法：循环条件是 TPOS < n，而游标推进却在 done==0 块内。
# 取完一个 token 后面还有字符时 TPOS 卡住 → 死循环 → 无声卡死。
new = """    while TPOS < n {
        if done == 0 {
            c = load8(&LINE + TPOS);
            TPOS = TPOS + 1;
            if c == 32 {
                if i > 0 {
                    done = 1;
                }
            } else {
                if i < 15 {
                    store8(&TOK + i, c);
                    i = i + 1;
                }
            }
        }
    }"""
if old not in s:
    sys.stderr.write("ANCHOR MISS\n"); sys.exit(3)
open(p, 'w').write(s.replace(old, new, 1))
PY
[ $? = 0 ] || { echo "M1 锚点未命中"; exit 1; }
report "M1" "捕获"

# M2 —— 无条件推进游标：第一次调用吃掉整行，带参数的命令全部丢参数
echo "=== M2 next_tok 无条件推进（参数丢失） ==="
apply_src '    while done == 0 {
        if TPOS >= n {' '    while TPOS < n {
        if 0 {' || { echo "M2 锚点未命中"; exit 1; }
report "M2" "捕获"

# M3 —— VM 的 ADD 做完不弹栈：栈指针错乱，结果不再是 8
echo "=== M3 VM ADD 不弹栈 ==="
apply_src '                STACK[sp - 2] = STACK[sp - 2] + STACK[sp - 1];
                sp = sp - 1;' '                STACK[sp - 2] = STACK[sp - 2] + STACK[sp - 1];' || { echo "M3 锚点未命中"; exit 1; }
report "M3" "捕获"

# M4 —— 模拟器把第一个按键预置进 DR（Unicorn 读钩子在读之前触发，
#       于是首字节被覆盖丢失）：回显缺第一个字符
echo "=== M4 模拟器预置首字节（回显吃掉首字符） ==="
python3 - "$RUN" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
a = "    def prime():"
b = "    prime()  # 预置\n\n    def prime2():"
if a not in s:
    sys.stderr.write("ANCHOR MISS\n"); sys.exit(3)
open(p, 'w').write(s.replace(a, b, 1))
PY
[ $? = 0 ] || { echo "M4 锚点未命中"; exit 1; }
report "M4" "捕获"

echo
echo "kern64sysmut: $pass 符合预期 / $fail 不符合"
restore
[ "$fail" = 0 ] || exit 1
exit 0
