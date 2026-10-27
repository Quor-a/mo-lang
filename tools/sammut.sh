#!/bin/bash
# sammut —— 后缀自动机（lib/sam.mo）的变异验证
#
# 目的：证明 tests/142_sam.mo 的 48 项断言**非空转**。
# 只看"全过"说明不了任何事 —— 得把实现故意改坏，确认判据会变红。
#
# 六个变异各打一条因果链：
#   M1 克隆时不复制转移   → 克隆状态没有出边，查询提前失败
#   M2 克隆条件放宽       → 该克隆时不克隆，len/link 关系被破坏
#   M3 cnt 按 len 升序传播 → endpos 计数错（必须降序才是拓扑序）
#   M4 nsub 不减 link      → 不同子串数算错
#   M5 克隆状态的 cnt=1    → 克隆是"合并出来的"，不应自带一次出现
#   M6 查不到转移返回初态 → 子串判定恒真
#
# sam.mo 是**库**不是编译器，所以每个变异只需重编测试，不必重建 moc。
# 但要防"临时 elf 被复用"：每次都写到 build/ 下的独立路径。
#
# 还原机制（本项目栽过多次，这里一次做齐）：
#   · 备份取自**干净**源码，只覆盖不删除，收尾才清；
#   · trap 保证中断后也能还原；
#   · 开工前自愈：若源码里已出现任一变异串，先用同一份映射反向替换。
HERE=$(cd "$(dirname "$0")/.." && pwd)
SRC="$HERE/lib/sam.mo"
BAK="$HERE/build/sammut_sam.bak"
ELF="$HERE/build/sammut_142.elf"
mkdir -p "$HERE/build"

MUT_OLD=(
'    let e: i64 = SA_HD[src];'
'    SA_LN[cl] = SA_LN[p] + 1;'
'    i = SA_N - 1;
    while i > 0 {'
'        s = s + SA_LN[v] - SA_LN[SA_LK[v]];'
'    SA_CN[cl] = 0;'
'fn sam_get(p: i64, c: i64) -> i64 {
    let e: i64 = SA_HD[p];
    while e >= 0 {
        if SA_CH[e] == c {
            return SA_TO[e];
        }
        e = SA_NX[e];
    }
    return -1;
}'
)
MUT_NEW=(
'    let e: i64 = -1;'
'    SA_LN[cl] = SA_LN[q];'
'    i = 1;
    while i < SA_N {'
'        s = s + SA_LN[v];'
'    SA_CN[cl] = 1;'
'fn sam_get(p: i64, c: i64) -> i64 {
    let e: i64 = SA_HD[p];
    while e >= 0 {
        if SA_CH[e] == c {
            return SA_TO[e];
        }
        e = SA_NX[e];
    }
    return 0;
}'
)
MUT_NAME=(
"M1 克隆时不复制转移"
"M2 克隆状态的 len 取成 len[q]"
"M3 cnt 按 len 升序传播"
"M4 nsub 不减 len[link]"
"M5 克隆状态 cnt 初值 1"
"M6 查不到转移返回初态"
)

restore() {
    if [ -f "$BAK" ]; then cp "$BAK" "$SRC"; fi
}

# 自愈：源码若停在变异态，反向替换回去（同一份映射，索引一致）
heal() {
    python3 - "$SRC" <<'PY'
import sys, os
p = sys.argv[1]
s = open(p).read()
pairs = [
('    let e: i64 = -1;', '    let e: i64 = SA_HD[src];'),
('    SA_LN[cl] = SA_LN[q];', '    SA_LN[cl] = SA_LN[p] + 1;'),
('    i = 1;\n    while i < SA_N {', '    i = SA_N - 1;\n    while i > 0 {'),
('        s = s + SA_LN[v];', '        s = s + SA_LN[v] - SA_LN[SA_LK[v]];'),
('    SA_CN[cl] = 1;', '    SA_CN[cl] = 0;'),
('    return 0;\n}', None),
]
n = 0
for old, new in pairs[:5]:
    if old in s:
        s = s.replace(old, new); n += 1
# sam_get 的 return 0 —— 只在该函数体内还原
i = s.find('fn sam_get(p: i64, c: i64) -> i64 {')
if i >= 0:
    j = s.find('\n}', i)
    seg = s[i:j]
    if seg.rstrip().endswith('return 0;'):
        seg = seg.rstrip()[: -len('return 0;')] + 'return -1;'
        s = s[:i] + seg + s[j:]
        n += 1
if n:
    open(p, 'w').write(s)
print(n)
PY
}

trap restore EXIT INT TERM

apply() { # apply <旧串> <新串>
    python3 - "$SRC" "$1" "$2" <<'PY'
import sys
p, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(p).read()
c = s.count(old)
if c != 1:
    sys.stderr.write("锚点命中 %d 次（应为 1）\n" % c); sys.exit(2)
open(p, 'w').write(s.replace(old, new))
PY
}

run_142() { # 返回 0 = 测试通过
    rm -f "$ELF"
    if ! "$HERE/bin/moc" "$HERE/tests/142_sam.mo" "$ELF" >/dev/null 2>&1; then
        return 3
    fi
    timeout 120 "$ELF" >/dev/null 2>&1
    return $?
}

FAILM=0
echo "== 基线（源码必须干净）=="
H=$(heal); [ "$H" != "0" ] && echo "  自愈：修回 $H 处残留变异"
cp "$SRC" "$BAK"
RC=0; run_142 || RC=$?
if [ "$RC" = "0" ]; then echo "  ✓ 基线通过"; else
    echo "  ✗ 基线未通过（rc=$RC），后续结论无意义"; restore; exit 1; fi

for k in $(seq 0 $(( ${#MUT_NAME[@]} - 1 ))); do
    echo "---- ${MUT_NAME[$k]} ----"
    restore
    if ! apply "${MUT_OLD[$k]}" "${MUT_NEW[$k]}"; then
        echo "  ✗ 锚点未命中"; FAILM=$((FAILM+1)); continue
    fi
    RC=0; run_142 || RC=$?
    if [ "$RC" != "0" ]; then
        OUT=$(timeout 200 "$ELF" 2>&1 | grep "ran ")
        echo "  ✓ 变异被捕获（rc=$RC，$OUT）"
    else
        echo "  ✗ 变异**未被捕获**，测试仍全绿 —— 断言空转。"
        FAILM=$((FAILM+1))
    fi
done

restore
echo ""
if [ "$FAILM" = "0" ]; then echo "== 全部变异均被捕获 =="; exit 0; fi
echo "== 有 $FAILM 个变异未被捕获 =="; exit 1
