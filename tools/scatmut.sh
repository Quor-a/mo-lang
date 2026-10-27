#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────
#  scat 变异验证（str 的 '+' / '+=' 拼接）
#
#  只看 "ran 41, failed 0" 证明不了任何事 —— 断言可能压根没参与判断。
#  这里逐个把实现改坏，确认测试**真的变红**。
#
#  五个变异分两层：
#    M1  编译器 '+'  退回地址相加   → 验证类型分派真的走了拼接
#    M5  编译器 '+=' 退回地址相加   → 复合赋值走的是另一条代码路径，
#                                     不单独验证的话 M1 抓不到它
#    M2  库侧：不写结尾 NUL         → 验证"内容正确"不是靠长度蒙的
#    M3  库侧：reset 把内存还给内核 → 验证 reuse-* 真的在测复用
#    M4  库侧：复制计数写死为 1     → 验证 copy-* 真的在量复制量
#
#  🔴 三条必须遵守的纪律（都是本项目栽过的）：
#    1) 备份只在最后删一次。曾经在 restore() 里顺手 rm 备份，
#       于是第二次还原是空操作、变异留在源码里，脚本却照样打印全绿。
#    2) 收尾必须 **逐字节 diff** 核对，不能 grep 变异串 ——
#       后者会被"源码里本来就有同样一段"骗过。
#    3) 变异必须直接回到缺陷状态。曾经把"改点东西"当成变异，
#       结果代码变了、因果链没动，测试照样绿。
# ─────────────────────────────────────────────────────────────────────────
set -u
cd "$(dirname "$0")/.."
ROOT=$PWD
LIB=lib/scat.mo
P4=src/mo/compiler_part4.mo
P5=src/mo/compiler_part5.mo
BAK_LIB=$(mktemp /tmp/scatmut_lib.XXXXXX)
BAK_P4=$(mktemp /tmp/scatmut_p4.XXXXXX)
BAK_P5=$(mktemp /tmp/scatmut_p5.XXXXXX)
cp "$LIB" "$BAK_LIB"
cp "$P4" "$BAK_P4"
cp "$P5" "$BAK_P5"

# 🔴 必须**每次都拷贝**，不能用"已还原"标志跳过。
rebuild() {
    make sync >/dev/null 2>&1
    ./build.sh self bin/seed >/dev/null 2>&1
}
restore() {
    cp "$BAK_LIB" "$LIB"
    cp "$BAK_P4" "$P4"
    cp "$BAK_P5" "$P5"
    rebuild
}
trap restore EXIT

run_test() {
    rm -rf /tmp/mot; mkdir -p /tmp/mot
    cp lib/*.mo /tmp/mot/ 2>/dev/null
    cp tests/130_scat.mo /tmp/mot/test.mo
    ( cd /tmp/mot && "$ROOT/bin/moc" ) >/dev/null 2>&1
    chmod +x /tmp/mot/out.elf 2>/dev/null
    # 🔴 崩溃时程序一行都不打印。只取最后一行的话输出为空，
    #    "✓ 变异被捕获 → " 后面什么都没有 —— 看着像脚本写坏了，
    #    其实是"被捕获"的最强证据。把退出码一并带上，别让结论靠猜。
    local out rc
    out=$( cd /tmp/mot && ./out.elf 2>&1 ); rc=$?
    last=$(printf '%s\n' "$out" | tail -1)
    if [ -z "$last" ]; then last="(无输出, exit=$rc)"; fi
    printf '%s\n' "$last"
}

# 基线
restore
base=$(run_test)
if echo "$base" | grep -q "failed 0"; then
    echo "✓ 基线：$base"
else
    echo "✗ 基线就没过：$base"; exit 1
fi

# 施加变异。old 必须在文件里**恰好出现一次** ——
# 否则要么是锚点写错，要么是替换到了别处，两者都会让结论失效。
apply() {
    python3 - "$1" "$2" "$3" <<'PY'
import sys
p, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(p).read()
c = s.count(old)
assert c == 1, "锚点不唯一或找不到: count=%d" % c
open(p, 'w').write(s.replace(old, new))
PY
}

mutate_lib() {
    local name="$1" old="$2" new="$3"
    cp "$BAK_LIB" "$LIB"
    if ! apply "$LIB" "$old" "$new"; then echo "✗ $name 变异未能施加"; exit 1; fi
    local out
    out=$(run_test)
    if echo "$out" | grep -q "failed 0"; then
        echo "✗ $name 变异未被捕获（测试仍全过）"
        exit 1
    else
        echo "✓ $name 变异被捕获 → $out"
    fi
}

mutate_cmp() {
    local name="$1" file="$2" old="$3" new="$4"
    cp "$BAK_P4" "$P4"; cp "$BAK_P5" "$P5"
    if ! apply "$file" "$old" "$new"; then echo "✗ $name 变异未能施加"; exit 1; fi
    rebuild
    local out
    out=$(run_test)
    if echo "$out" | grep -q "failed 0"; then
        echo "✗ $name 变异未被捕获（测试仍全过）"
        exit 1
    else
        echo "✓ $name 变异被捕获 → $out"
    fi
    # 编译器必须立刻还原，否则后续变异跑在坏编译器上
    cp "$BAK_P4" "$P4"; cp "$BAK_P5" "$P5"; rebuild
}

# ── 编译器侧 ──
mutate_cmp "M1 '+' 退回地址相加" "src/mo/compiler_part4.mo" \
    "                if g_str_cat() != 0 { return -1; }" \
    "                g_add();"

# 🔴 M5 必须回到**真实缺陷状态**。第一版把 `if ty_kind(clt) == 10` 改成 `if 0`，
#    结果 str 的 '+=' 落到 else 分支被类型检查挡住 —— 编译期报错、out.elf 没生成，
#    脚本照样判"被捕获"。可那验的是"类型检查存在"，不是"拼接是对的"。
#    真正要抓的是 1.121 修掉的那个：类型检查都在、运算却走地址相加 →
#    实测段错误（exit 139），或者静默给出偏移后的串。所以这里只换运算。
mutate_cmp "M5 '+=' 退回地址相加" "src/mo/compiler_part5.mo" \
    "                if g_str_cat() != 0 { return -1; }
            } else {
" \
    "                g_compound(cop, cdv, cdk);
            } else {
"

# ── 库侧 ──
mutate_lib "M2 不写结尾 NUL" \
    "    store8(p + n + m, 0);
    # 复制量" \
    "    # 复制量"

mutate_lib "M3 reset 把容量也归零" \
    "    SB_PTR = SB_BASE;" \
    "    SB_PTR = SB_BASE; SB_END = SB_BASE;"

mutate_lib "M4 复制计数写死为 1" \
    "    SB_COPY = SB_COPY + n + m;" \
    "    SB_COPY = SB_COPY + 1;"

# 收尾核对：与备份逐字节相同
restore
ok=1
for pair in "$BAK_LIB:$LIB" "$BAK_P4:$P4" "$BAK_P5:$P5"; do
    b=${pair%%:*}; f=${pair##*:}
    if diff -q "$b" "$f" >/dev/null; then
        echo "✓ $f 已还原（与备份逐字节相同）"
    else
        echo "✗ $f 还原失败"; diff "$b" "$f" | head -10; ok=0
    fi
done

trap - EXIT
rm -f "$BAK_LIB" "$BAK_P4" "$BAK_P5"
[ $ok = 1 ] || exit 1
exit 0
