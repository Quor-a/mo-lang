#!/bin/bash
# acmut —— Aho–Corasick（lib/ac.mo）的变异验证
#
# 目的：证明 tests/145_ac.mo 的 41 项断言**非空转**。
# 只看"全过"说明不了任何事 —— 得把实现故意改坏，确认判据会变红。
#
# 五个变异各打一条因果链：
#   M1 failure link 恒 0        → 后缀关系断掉，跨边界的匹配漏报
#   M2 不做输出合并             → 真后缀上的模式（b 之于 ab）报不出来
#   M3 BFS 队列改 LIFO（DFS）   → ac_merge 依赖 fail[v] 已合并完，DFS 会破坏
#   M4 ac_step 失配直接回根     → 多跳 fail 链只跳一跳，漏报
#   M5 同一位置的 pid 不排序    → 输出顺序与朴素枚举不再逐项一致
#
# 还原机制（本项目栽过多次，这里一次做齐）：
#   · 备份在 build/ 下（/tmp 会被沙盒清掉，栽过）；
#   · 只覆盖不删除，收尾才清；
#   · trap 保证被强杀后也能还原；
#   · 开工前自愈：若源码已停在变异态，用同一份映射反向替换。
HERE=$(cd "$(dirname "$0")/.." && pwd)
SRC="$HERE/lib/ac.mo"
BAK="$HERE/build/acmut_ac.bak"
MOC="$HERE/bin/moc"
PY="$HERE/build/acmut_pairs.py"
mkdir -p "$HERE/build"

# 干净 -> 变异。用 Python 精确子串替换（不用 sed 正则：本项目栽过
# "锚点手工验证能匹配、脚本里却恒判未生效"）。
cat > "$PY" <<'PYEOF'
import sys
PAIRS = [
("M1 failure link 恒 0",
 "            AC_FL[u] = ac_fchild(v, c, u);",
 "            AC_FL[u] = 0;"),
("M2 不做输出合并",
 "        ac_merge(v);",
 "        ac_merge(0);"),
("M3 BFS 队列改 LIFO(DFS)",
 "        let v: i64 = AC_Q[qh];\n        qh = qh + 1;",
 "        let v: i64 = AC_Q[qt - 1];\n        qt = qt - 1;"),
("M4 失配直接回根",
 "        AC_NFB = AC_NFB + 1;\n        v = AC_FL[v];",
 "        AC_NFB = AC_NFB + 1;\n        v = 0;"),
# M5 的变异串必须是**完整三行**：只写一行的话，它是干净串的子串，
#    自愈（反向替换）会把干净的三行又扩成五行 —— 本轮就发生过一次，
#    源码被"修复动作"改成交换语句重复两遍，基线直接 failed 4。
("M5 同位置 pid 不排序",
 "        let t: i64 = AC_TB[i];\n        AC_TB[i] = AC_TB[m];\n        AC_TB[m] = t;",
 "        let t: i64 = AC_TB[i];\n        AC_TB[i] = AC_TB[i];\n        AC_TB[m] = AC_TB[m];"),
]
mode = sys.argv[1]
path = sys.argv[2]
s = open(path).read()
if mode == "heal":
    n = 0
    for name, good, bad in PAIRS:
        if bad in s:
            s = s.replace(bad, good); n += 1
    if n:
        open(path, "w").write(s)
    print("HEALED %d" % n)
elif mode == "names":
    for i, (name, good, bad) in enumerate(PAIRS):
        print("%d\t%s" % (i, name))
elif mode == "count":
    print(len(PAIRS))
elif mode == "apply":
    idx = int(sys.argv[3])
    name, good, bad = PAIRS[idx]
    if good not in s:
        print("ANCHOR-MISS"); sys.exit(3)
    open(path, "w").write(s.replace(good, bad, 1))
    # 🔴 写回校验：沙盒文件系统有写入可见性延迟，写完立刻 cp 会读到
    #    旧内容 —— 于是"变异未生效"被误报成"变异未被捕获"。
    #    本轮 M2 就中过一次：手动应用时测试挂 6 项，脚本里却全过。
    reread = open(path).read()
    if bad not in reread:
        print("WRITE-INVISIBLE"); sys.exit(4)
    print("OK")
elif mode == "check":
    # 收尾核对：任一变异串还留在源码里就报错
    left = 0
    for name, good, bad in PAIRS:
        if bad in s:
            left += 1
    print("LEFT %d" % left)
    sys.exit(1 if left else 0)
PYEOF

restore() { [ -f "$BAK" ] && cp "$BAK" "$SRC"; return 0; }
trap restore EXIT INT TERM

run_test() {
    local dir="$HERE/build/acmut_run"
    rm -rf "$dir" && mkdir -p "$dir"
    cp "$HERE"/lib/*.mo "$dir/" 2>/dev/null
    cp "$HERE/tests/145_ac.mo" "$dir/test.mo"
    ( cd "$dir" && timeout 30 "$MOC" test.mo out.elf ) >/dev/null 2>&1
    if [ ! -f "$dir/out.elf" ]; then echo "COMPILE-FAIL"; return 2; fi
    ( cd "$dir" && timeout 20 ./out.elf ) 2>&1 | tail -1
    return ${PIPESTATUS[0]}
}

echo "=== acmut: $(basename "$SRC") ==="
python3 "$PY" heal "$SRC"
cp "$SRC" "$BAK"

echo -n "基线（必须全过）: "
out=$(run_test); rc=$?
echo "$out (rc=$rc)"
if [ "$rc" != "0" ]; then echo "❌ 基线就没过，变异结果无意义"; exit 1; fi

N=$(python3 "$PY" count "$SRC")
allcaught=1
i=0
while [ "$i" -lt "$N" ]; do
    name=$(python3 "$PY" names "$SRC" | awk -F'\t' -v k="$i" '$1==k{print $2}')
    r=$(python3 "$PY" apply "$SRC" "$i")
    sync
    if [ "$r" != "OK" ]; then
        echo "⚠ $name 变异未生效（$r）"; allcaught=0
    else
        out=$(run_test); rc=$?
        if [ "$rc" != "0" ]; then
            echo "✓ $name 变异被捕获 -> $out (rc=$rc)"
        else
            echo "✗ $name 未被捕获 -> $out (rc=$rc)"; allcaught=0
        fi
    fi
    restore
    i=$((i+1))
done

python3 "$PY" check "$SRC" || allcaught=0
[ -f "$BAK" ] || { echo "❌ 备份缺失"; allcaught=0; }

if [ "$allcaught" = "1" ]; then echo "=== 全部变异被捕获 ==="; else echo "=== 有变异未被捕获 ==="; fi
[ "$allcaught" = "1" ]
