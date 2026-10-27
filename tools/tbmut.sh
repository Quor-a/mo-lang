#!/bin/bash
# tbmut —— trait bound 的变异验证
#
# 目的：证明 tbtest 的断言**非空转**。只看"11/11 全过"说明不了任何事 ——
# 得把实现故意改坏，确认判据会变红。
#
# 四个变异分两类：
#   M1/M2/M3 让 bound **永不拒绝**  → 负例 C/D 应当放行，测试变红
#   M5      让 impl 全部记成 interface 0 → 正例被**误拒**，测试变红
# M5 是必要的：只测"该拒的拒了"，分不清"检查生效"和"见谁都拒"。
#
# 还原机制（本项目栽过多次）：
#   · 备份取自**干净**源码，且只删不重建；
#   · trap 保证中断后也能还原；
#   · 每次重建前 rm -f bin/moc —— cp 与上次构建落在同一秒时 make 会
#     认为产物仍更新，于是测的是**上一个**变异的编译器。
HERE=$(cd "$(dirname "$0")/.." && pwd)
SRC="$HERE/src/mo/compiler_part5.mo"
BAK="$HERE/build/tbmut_part5.bak"
mkdir -p "$HERE/build"

restore() {
    if [ -f "$BAK" ]; then cp "$BAK" "$SRC"; (cd "$HERE" && make sync >/dev/null 2>&1); fi
}
trap restore EXIT INT TERM

cp "$SRC" "$BAK"

apply() { # apply <锚点文件> <旧串> <新串>
    python3 - "$SRC" "$1" "$2" <<'PY'
import sys
p, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(p).read()
if s.count(old) != 1:
    sys.stderr.write("锚点命中 %d 次（应为 1）\n" % s.count(old)); sys.exit(2)
open(p, 'w').write(s.replace(old, new))
PY
}

build() {
    (cd "$HERE" && rm -f bin/moc && make sync >/dev/null 2>&1 && make bin/moc >/dev/null 2>&1)
}

run_case() { # run_case <名字> <锚点旧> <锚点新>
    echo "---- $1 ----"
    restore
    if ! apply "$2" "$3"; then echo "  ✗ 锚点未命中"; FAILM=$((FAILM+1)); return; fi
    if ! build; then echo "  ✗ 构建失败"; FAILM=$((FAILM+1)); return; fi
    OUT=$(bash "$HERE/tools/tbtest.sh" 2>&1); RC=$?
    N=$(echo "$OUT" | grep -c "✗")
    if [ "$RC" != "0" ]; then
        echo "  ✓ 变异被捕获（$N 项变红）"
    else
        echo "  ✗ 变异**未被捕获**，测试仍全绿 —— 断言空转。"
        echo "$OUT" | tail -4
        FAILM=$((FAILM+1))
    fi
}

FAILM=0
echo "== 基线（源码必须干净）=="
restore; build
OUT=$(bash "$HERE/tools/tbtest.sh" 2>&1); RC=$?
if [ "$RC" = "0" ]; then echo "  ✓ 基线通过"; else echo "  ✗ 基线未通过，后续结论无意义"; echo "$OUT" | tail -6; exit 1; fi

run_case "M1 bound 检查永不拒绝" \
    'if gen_has_impl(kif, tn) == 0 {' \
    'if 0 {'

run_case "M2 恒判定为已 impl" \
    'fn gen_has_impl(iface: i64, tname: i64) -> i64 {
    let v: i64 = 0;' \
    'fn gen_has_impl(iface: i64, tname: i64) -> i64 {
    return 1;
    let v: i64 = 0;'

run_case "M3 不记录 bound 个数" \
    'store64(heap + O_GBC + g * 128 + nt * 8, nbnd);' \
    'store64(heap + O_GBC + g * 128 + nt * 8, 0);'

run_case "M5 impl 全部记成 interface 0" \
    'store64(heap + O_VTK + v * 8, k);' \
    'store64(heap + O_VTK + v * 8, 0);'

restore
build
echo ""
if [ "$FAILM" = "0" ]; then echo "== 全部变异均被捕获 =="; exit 0; fi
echo "== 有 $FAILM 个变异未被捕获 =="; exit 1
