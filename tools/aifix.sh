#!/bin/bash
# aifix —— 修复墨语言 bug 的**闭环**（给 AI 和人用）
#
#   bash tools/aifix.sh --file <路径> \
#                       --old '<原文>' --new '<新文>' \
#                       --test '<验证命令>' [--rebuild '<强制重建命令>'] [--boot] [--no-mut]
#
# 为什么需要它
# ------------
# 「改完代码跑一遍测试」不等于「修好了」。本项目反复出现过这几种假象：
#
#   · 改的是 src/compiler.mo，下一次 make sync 被分片覆盖 → 改动消失，
#     测试照旧全绿（v1.14x 踩过：搜索自己刚写的关键词，返回 0 个结果）
#   · 源码是干净的，但 bin/ 里的编译器还是上一轮变异留下的 →
#     测的是旧产物，症状离根因十万八千里（v1.136）
#   · 测试本来就通过 → 改对改错都一样（v1.141：SA_NCL=0，克隆分支从未进入）
#
# aifix 把这三条变成硬步骤：
#
#   1. 补丁只能打在真正的源头上 —— 传 src/compiler.mo 直接拒绝
#   2. 每次都强制重建，不留上一轮的产物
#   3. 修完自动做一次**变异**：把 --new 换回 --old，测试**必须失败**。
#      失败 = 这条修复真被钉住了；仍然通过 = 测试根本没覆盖到，报告出来
#   4. 可选的 --boot：跑自举，改动影响代码生成而没镜像 seed 时立刻报不一致
#
# --old / --new 的写法
# --------------------
#   · 直接给字符串（shell 里用单引号，可含真实换行）
#   · 以 @ 开头表示「从文件读」，多行补丁**一律用这个**，
#     避免 shell 引号与转义改变内容

set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

FILE=""
OLD=""
NEW=""
TEST=""
REBUILD=""
BOOT="no"
NOMUT="no"
KEEP="yes"

while [ $# -gt 0 ]; do
    case "$1" in
        --file)    FILE=$2;     shift 2 ;;
        --old)     OLD=$2;      shift 2 ;;
        --new)     NEW=$2;      shift 2 ;;
        --test)    TEST=$2;     shift 2 ;;
        --rebuild) REBUILD=$2;  shift 2 ;;
        --boot)    BOOT="yes";  shift ;;
        --no-mut)  NOMUT="yes"; shift ;;
        --revert-on-fail) KEEP="no"; shift ;;
        *) echo "aifix: 未知参数 '$1'"; exit 2 ;;
    esac
done

if [ -z "$FILE" ] || [ -z "$OLD" ] || [ -z "$NEW" ] || [ -z "$TEST" ]; then
    echo "用法: aifix --file <路径> --old <原文|@文件> --new <新文|@文件> --test <命令>"
    exit 2
fi

if [ ! -f "$FILE" ]; then
    echo "aifix: 文件不存在: $FILE"
    exit 2
fi

# ---------------------------------------------------------------------------
# 守卫 1：补丁不能打在生成物上
# ---------------------------------------------------------------------------
case "$FILE" in
    src/compiler.mo)
        echo "❌ 拒绝：$FILE 是 src/mo/compiler_part*.mo 拼接出来的生成物。"
        echo "   改编译器要改 src/mo/ 下的片段，改完 aifix 会自动 make sync。"
        echo "   （直接改这里，下一次 sync 就把你的改动冲掉了 —— 而且不报错）"
        exit 2
        ;;
esac

# ---------------------------------------------------------------------------
# 备份放在 build/ 下，不放 /tmp
# /tmp 会被清理，源码一旦停在变异态、备份又没了，只能手工还原（v1.128）
# ---------------------------------------------------------------------------
BAKDIR=build/aifix
mkdir -p "$BAKDIR"
BAK_ORIG="$BAKDIR/$(echo "$FILE" | tr '/' '_').orig"
BAK_NEW="$BAKDIR/$(echo "$FILE" | tr '/' '_').new"
cp "$FILE" "$BAK_ORIG"

apply() {   # apply <old> <new> —— 精确子串替换，用 python 不用 sed
    python3 - "$FILE" "$1" "$2" <<'PYEOF'
import sys
path, old, new = sys.argv[1], sys.argv[2], sys.argv[3]

def rd(s):
    if s.startswith('@'):
        with open(s[1:], encoding='utf-8') as f:
            return f.read()
    return s

o, n = rd(old), rd(new)
src = open(path, encoding='utf-8').read()
c = src.count(o)
if c == 0:
    print("NO_MATCH")
    sys.exit(1)
if c > 1:
    print("MULTI_MATCH %d" % c)
    sys.exit(1)
open(path, 'w', encoding='utf-8').write(src.replace(o, n))
print("OK")
PYEOF
}

rebuild() {
    # 分片改完必须重新拼接（src/compiler.mo 是生成的）
    case "$FILE" in
        src/mo/compiler_part*.mo)
            make sync >/dev/null 2>&1 || { echo "❌ make sync 失败"; return 1; }
            rm -f bin/moc
            make bin/moc >/dev/null 2>&1 || { echo "❌ 重建 bin/moc 失败"; return 1; }
            ;;
        src/*)
            rm -f bin/moc
            make bin/moc >/dev/null 2>&1 || { echo "❌ 重建 bin/moc 失败"; return 1; }
            ;;
    esac
    if [ -n "$REBUILD" ]; then
        bash -c "$REBUILD" >/dev/null 2>&1 || { echo "❌ --rebuild 失败"; return 1; }
    fi
    return 0
}

restore_new() {
    cp "$BAK_NEW" "$FILE" 2>/dev/null || return 0
    case "$FILE" in
        src/mo/compiler_part*.mo) make sync >/dev/null 2>&1 ;;
    esac
}

echo "=== aifix : $FILE ==="

# ---------------------------------------------------------------------------
# 1) 应用补丁
# ---------------------------------------------------------------------------
R=$(apply "$OLD" "$NEW")
if [ "$R" != "OK" ]; then
    echo "❌ 补丁应用失败: $R"
    case "$R" in
        NO_MATCH)     echo "   --old 在文件里找不到（内容被 shell 改过？改用 @文件）" ;;
        MULTI_MATCH*) echo "   --old 出现多次，无法判定改哪一处 —— 请把上下文写长一点" ;;
    esac
    exit 2
fi
cp "$FILE" "$BAK_NEW"
echo "✓ 补丁已应用（--old 唯一匹配）"

# 中断时保证源码停在**修复态**，不是变异态
trap 'echo; echo "⚠ 中断 —— 恢复源码到修复态"; restore_new; exit 130' INT TERM

# ---------------------------------------------------------------------------
# 2) 强制重建 + 跑测试
# ---------------------------------------------------------------------------
if ! rebuild; then
    echo "❌ 重建失败"
    exit 1
fi
echo "✓ 已强制重建"

bash -c "$TEST" >"$BAKDIR/test_fixed.log" 2>&1
RC_FIX=$?
if [ "$RC_FIX" -eq 0 ]; then
    echo "✓ 修复后测试通过 (rc=0)"
else
    echo "❌ 修复后测试仍然失败 (rc=$RC_FIX)"
    tail -20 "$BAKDIR/test_fixed.log"
    if [ "$KEEP" = "no" ]; then
        cp "$BAK_ORIG" "$FILE"
        echo "   源码已还原到修复前"
    else
        echo "   源码保持在修复态，便于继续迭代（--revert-on-fail 可自动还原）"
    fi
    exit 1
fi

# ---------------------------------------------------------------------------
# 3) 变异：把 --new 换回 --old，测试**必须失败**
# ---------------------------------------------------------------------------
if [ "$NOMUT" = "yes" ]; then
    echo "· 跳过变异（--no-mut）"
else
    R=$(apply "$NEW" "$OLD")
    if [ "$R" != "OK" ]; then
        echo "❌ 无法回到变异态: $R"
        restore_new
        exit 1
    fi
    rebuild >/dev/null 2>&1
    bash -c "$TEST" >"$BAKDIR/test_mutant.log" 2>&1
    RC_MUT=$?
    if [ "$RC_MUT" -ne 0 ]; then
        echo "✓ 变异后测试失败 (rc=$RC_MUT) ← 修复被钉住了"
    else
        echo "❌ 变异后测试仍然通过 —— 这条修复没被钉住"
        echo "   意思：把修复撤掉，测试照样全绿。要么测试没覆盖到这个缺陷，"
        echo "   要么判据只是「能编译 / 退出码 0」。先补判据，再谈修好了。"
        restore_new
        rebuild >/dev/null 2>&1
        exit 1
    fi
    restore_new
    rebuild >/dev/null 2>&1
    echo "✓ 已还原到修复态"
fi

# ---------------------------------------------------------------------------
# 4) 可选：自举
# ---------------------------------------------------------------------------
if [ "$BOOT" = "yes" ]; then
    if bash verify_bootstrap.sh >"$BAKDIR/boot.log" 2>&1; then
        echo "✓ 自举三级一致"
    else
        echo "❌ 自举不一致 —— 改动影响代码生成却没在 src/asm/*.s 里镜像"
        tail -20 "$BAKDIR/boot.log"
        exit 1
    fi
fi

echo
echo "=== 结论：修复有效，且被测试钉住 ==="
exit 0
