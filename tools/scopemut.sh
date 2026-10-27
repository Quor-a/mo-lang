#!/bin/bash
# scopemut —— 结构化并发的变异验证
#
# 19 项断言全绿证明不了任何事。五条最关键的语义必须各自有一个
# "对应的坏版本"会变红，否则它们可能只是在比两个恒等的数。
#
# 变异脚本自身的纪律（本项目已栽过三次）：
#   · 每次变异都从**原始副本**重新拷贝，不依赖上一次是否还原成功
#   · trap 覆盖 EXIT/INT/TERM —— 上次被强杀后源码停在变异态，基线全红
#   · 收尾用 diff 逐字节核对，并保留备份副本
#   · 🔴 锚点定义在 preflight **之前**，污染时自动反向替换自愈
HERE=$(cd "$(dirname "$0")/.." && pwd)
T="$HERE/tools/scopetest.sh"
SRC="$HERE/lib/scope.mo"
# 🔴 备份**不能放 /tmp**。本轮第一次跑被强杀，之后发现沙箱的 /tmp 被清空
#    —— 源码停在 M5 变异态，而备份一起没了，只能手工还原。
#    放在 build/ 下，与源码同一个文件系统、同一份生命周期。
BK="$HERE/build/scopemutbk"
OUT="$HERE/build/scopemutout.txt"
mkdir -p "$HERE/build"

# 锚点必须先于 preflight：自愈要用它们做反向替换。
A="$HERE/build/scopemutanchor"
rm -rf $A && mkdir -p $A

cat > $A/a1 <<'EOF'
    let slot: i64 = csp_go_hold(f, arg);
    if slot < 0 { return 0 - 1; }
    SC_CO[slot] = s;
    SC_CURCO[slot] = s;
    mutex_lock(&SC_LK);
    SC_LIVE[s] = SC_LIVE[s] + 1;
    SC_TOT[s] = SC_TOT[s] + 1;
    mutex_unlock(&SC_LK);
    csp_start(slot);
    return slot;
EOF
cat > $A/b1 <<'EOF'
    let slot: i64 = csp_go(f, arg);
    if slot < 0 { return 0 - 1; }
    SC_CO[slot] = s;
    SC_CURCO[slot] = s;
    mutex_lock(&SC_LK);
    SC_LIVE[s] = SC_LIVE[s] + 1;
    SC_TOT[s] = SC_TOT[s] + 1;
    mutex_unlock(&SC_LK);
    return slot;
EOF

cat > $A/a2 <<'EOF'
    let u: i64 = s;
    while u >= 0 {
        if SC_CANCEL[u] == 1 { r = 1; }
        u = SC_PARENT[u];
    }
EOF
cat > $A/b2 <<'EOF'
    # (变异 M2：不上溯祖先链 —— 只查自己所在的 scope)
    if SC_CANCEL[s] == 1 { r = 1; }
EOF

cat > $A/a3 <<'EOF'
    let p: i64 = SC_PARENT[s];
    while p >= 0 {
        if e != 0 {
            if SC_ERR[p] == 0 { SC_ERR[p] = e; }
        }
        SC_CANCEL[p] = 1;
        p = SC_PARENT[p];
    }
EOF
cat > $A/b3 <<'EOF'
    # (变异 M3：向上冒泡已移除)
EOF

cat > $A/a4 <<'EOF'
    let live: i64 = 1;
EOF
cat > $A/b4 <<'EOF'
    let live: i64 = 0;
EOF

cat > $A/a5 <<'EOF'
        SC_LIVE[s] = SC_LIVE[s] - 1;
EOF
cat > $A/b5 <<'EOF'
        SC_LIVE[s] = SC_LIVE[s] - 0;
EOF

check_src() {
    local bad=0
    # 原始锚点必须各出现一次
    grep -q "csp_go_hold(f, arg)" "$SRC" || { echo "✗ 原始锚点 csp_go_hold 缺失"; bad=1; }
    grep -q "SC_CANCEL\[p\] = 1"    "$SRC" || { echo "✗ 原始锚点 向上冒泡 缺失"; bad=1; }
    grep -q "let live: i64 = 1"     "$SRC" || { echo "✗ 原始锚点 close-join 缺失"; bad=1; }
    grep -q "SC_LIVE\[s\] = SC_LIVE\[s\] - 1" "$SRC" || { echo "✗ 原始锚点 存活计数 缺失"; bad=1; }
    # 变异标记必须一个都没有
    grep -q "csp_go(f, arg)"                  "$SRC" && { echo "✗ 源码处于 M1 变异态"; bad=1; }
    grep -qE "变异 M[0-9]+："             "$SRC" && { echo "✗ 源码处于 M2/M3 变异态"; bad=1; }
    grep -q "SC_LIVE\[s\] = SC_LIVE\[s\] - 0" "$SRC" && { echo "✗ 源码处于 M5 变异态"; bad=1; }
    return $bad
}

# 🔴 预习（preflight）：先在**不碰备份**的前提下确认 $SRC 本身是原始态。
#    本轮踩到的就是这个：上一轮被强杀，源码停在 M5 变异态；下一轮开工
#    时 `cp $SRC $BK/orig.mo` 把**污染版当成了原始版**，于是收尾的
#    `diff $BK/orig.mo $SRC` 两边同源 —— 恒等，什么都验不出来。
#    判据必须是"源码不含任何变异标记"，而不是"源码等于备份"。
#
#    第二次栽：手工修回**并不可靠** —— sed 改完看起来成功了（打印出来
#    是对的），实际没落盘，下一轮又被抓。所以这里不再要求人肉修回，
#    而是用同一份 a*/b* 锚点做 b→a 反向替换自愈，然后复检。
preflight() {
    if check_src; then return 0; fi
    echo "  检测到污染 → 用 a*/b* 锚点反向替换自愈…"
    python3 - "$SRC" "$A" <<'PY'
import sys
src, adir = sys.argv[1], sys.argv[2]
s = open(src).read()
n = 0
for i in range(1, 6):
    a = open("%s/a%d" % (adir, i)).read()
    b = open("%s/b%d" % (adir, i)).read()
    if b in s and a not in s:
        s = s.replace(b, a)
        n += 1
        print("    修回 M%d" % i)
if n:
    open(src, "w").write(s)
print("  HEALED %d" % n)
PY
    if check_src; then echo "  ✓ 自愈成功，继续"; return 0; fi
    echo "  ✗ 自愈失败，仍需人工介入：$SRC"
    echo "  （逐条对照 tools/scopemut.sh 顶部的 a*/b* 锚点）"
    exit 1
}
preflight

# 🔴 开工前先清残留。scopemut 每次跑要编译+执行 6 遍 structconc，被强杀
#    或沙盒重启时，./structconc 会作为孙进程活下来；2 核机器上两个实例
#    并存就能把彼此的调度时序拖歪，表现为基线偶发 "close 超时"。
#    本轮实测：清理前 2/2 次基线 31/1，清理后 3/3 次 32/0。
pkill -f "structconc" 2>/dev/null
sleep 1

rm -rf $BK && mkdir -p $BK "$HERE/build"
cp "$SRC" "$BK/orig.mo"
restore() { cp "$BK/orig.mo" "$SRC"; }
trap restore EXIT INT TERM

run() { timeout 400 bash "$T" > $OUT 2>&1; echo $?; }
summary() { grep -E "^通过" $OUT | tail -1; }

# 同上：确认被测的确实是 scope.mo
grep -q '"scope.mo"' "$HERE/examples/structconc.mo" || { echo "✗ 示例没有 import scope.mo"; exit 1; }

echo "== 基线 =="
B=$(run)
echo "$(summary)  (rc=$B)"
if [ "$B" != "0" ]; then
  echo "✗ 基线就没过，变异无意义"
  echo "  若上一次是被强杀留下的变异态，用：cp $BK/orig.mo $SRC"
  tail -5 $OUT; exit 1
fi

mut() {   # $1=编号 $2=说明 $3=原串文件 $4=新串文件
    cp "$BK/orig.mo" "$SRC"
    python3 - "$SRC" "$3" "$4" <<'PY'
import sys
p,af,bf=sys.argv[1],sys.argv[2],sys.argv[3]
s=open(p).read(); a=open(af).read(); b=open(bf).read()
n=s.count(a)
if n!=1:
    print("ANCHOR_MISS:%d"%n); sys.exit(1)
open(p,'w').write(s.replace(a,b))
PY
    if [ $? -ne 0 ]; then echo "  ✗ $1 $2 —— 锚点未命中，变异未生效"; return 0; fi
    local r; r=$(run)
    if [ "$r" = "0" ]; then
        echo "  ✗ $1 $2 —— 未被捕获（测试对此无感）"
        echo "     $(summary)"
    else
        echo "  ✓ $1 $2 —— 被捕获"
        echo "     $(summary)"
        grep -E "^  ✗" $OUT | head -4 | sed 's/^/       /'
        CAP=$((CAP+1))
    fi
}

CAP=0; TOT=0
echo "== 变异 =="
TOT=$((TOT+1)); mut M1 "spawn 不 hold（先跑后登记 → 归属错乱）" $A/a1 $A/b1
TOT=$((TOT+1)); mut M2 "sc_cancelled 不上溯祖先链（取消穿透不了嵌套）" $A/a2 $A/b2
TOT=$((TOT+1)); mut M3 "错误不向上冒泡（外层吞掉内层失败）" $A/a3 $A/b3
TOT=$((TOT+1)); mut M4 "close 不 join（直接返回）" $A/a4 $A/b4
TOT=$((TOT+1)); mut M5 "sc_exit 不减存活计数（应当响出来而不是挂住）" $A/a5 $A/b5

restore
# 🔴 收尾必须重建 bin/moc：最后一轮变异留下的是**变异版 moc**，而
#    `cp 备份 $SRC` 与它常常落在同一秒 —— make 只看 mtime，会认为
#    bin/moc 仍比 src/compiler.mo 新而**跳过重建**。
#    于是脚本跑完之后，整个项目一直在用一个被改坏的编译器跑测试：
#    v1.136 的 "empty case: got 0, want 42" 就是这样来的 —— 源码是
#    干净的，bin/moc 却还停在 M5（空 case 不穿透）。
#    **源码干净 ≠ 产物干净**，两个都要还原。
rm -f bin/moc
make bin/moc >/dev/null 2>&1
if diff -q "$BK/orig.mo" "$SRC" >/dev/null; then echo "== 源码已还原（diff 逐字节一致） =="
else echo "✗ 还原失败！源码仍处在变异状态"; exit 1; fi
trap - EXIT INT TERM
echo "（原始副本保留在 $BK/orig.mo）"
echo "捕获 $CAP / $TOT"
[ $CAP -ge 4 ]
