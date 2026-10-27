#!/bin/bash
# rootfscheck —— 校验一个墨语言 rootfs 是否真能跑（六层判据）
#
#   bash tools/rootfscheck.sh <rootfs>
#
# 每层对应一类"报错指向别处"的静默失效：
#   [1] 工具链实体     —— 缺 moc 时 proot 报的是 "No such file"
#   [2] work/ 可 chdir —— proot 报 can't chdir to '/work'
#   [3] 目录权限 ≥755  —— tracee 降权后 700 进不去，报 Permission denied
#   [4] 翻译器自包含   —— 动态链接缺 loader 时 execve 报 ENOENT
#   [5] 标准库齐备     —— 少 io.mo 时编译报错指向用户代码
#   [6] 端到端         —— 真跑一次编译 + 执行
R=${1:-/tmp/mo_rootfs}
fail=0
ck(){ if [ "$2" = "0" ]; then echo "  ok   $1"; else echo "  FAIL $1"; fail=$((fail+1)); fi; }

echo "rootfscheck: $R"
[ -d "$R" ] || { echo "rootfs 不存在"; exit 1; }

[ -x "$R/bin/moc" ];  ck "[1] bin/moc 存在且可执行" $?
[ -x "$R/bin/mo2x" ]; ck "[1] bin/mo2x 存在且可执行" $?
[ -d "$R/work" ];     ck "[2] work/ 存在" $?
(cd "$R/work" && touch .wtest && rm -f .wtest) 2>/dev/null; ck "[2] work/ 可 chdir 且可写" $?

bad=""
for d in "" bin lib work etc; do
    m=$(stat -c '%a' "$R/$d" 2>/dev/null)
    case "$m" in 755|775|777) ;; *) bad="$bad ${d:-<顶层>}=$m";; esac
done
[ -z "$bad" ]; ck "[3] 目录权限 ≥755${bad:+（问题: $bad）}" $?

if [ -e "$R/box64" ]; then
    [ -x "$R/box64" ]; ck "[4] box64 可执行" $?
    out=$(python3 "$(dirname "$0")/rootfsxlate.py" "$R")
    st=$?
    [ "$st" = "0" ] || [ "$st" = "1" ]; ck "[4] 翻译器自包含（$out）" $?
else
    echo "  --   [4] 无翻译器（宿主架构一致，跳过）"
fi

[ -f "$R/lib/io.mo" ]; ck "[5] lib/io.mo 存在" $?
[ "$(ls "$R"/lib/*.mo 2>/dev/null | wc -l)" -gt 50 ]; ck "[5] 标准库 >50 个" $?

if [ "$(uname -m)" = "x86_64" ]; then
    W=$(mktemp -d); cp "$R"/lib/*.mo "$W"/ 2>/dev/null
    printf 'import "io.mo";\nfn main() -> i64 {\n    print("rootfs ok\\n");\n    return 0;\n}\n' > "$W/test.mo"
    (cd "$W" && "$R/bin/moc" test.mo out.elf >/dev/null 2>&1 && ./out.elf 2>/dev/null | grep -q "rootfs ok")
    ck "[6] 端到端编译并运行" $?
    rm -rf "$W"
else
    echo "  --   [6] 宿主非 x86_64，跳过端到端"
fi

echo "rootfscheck: $([ $fail -eq 0 ] && echo 全部通过 || echo "$fail 项失败")"
exit $fail
