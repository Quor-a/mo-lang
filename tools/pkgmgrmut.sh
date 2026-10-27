#!/bin/bash
# pkgmgrmut —— 证明 pkgmgrtest 的判据**真的会响**（变异验证）
#
#   make pkgmgrmut
#
# 为什么必须做这一步
# ------------------
# 本项目反复栽在"验证机制自身静默失效"上：测试恒绿，但一条都没验到。
# 所以每个新测试都要配一组"把实现改回缺陷状态"的变异，确认判据会变红。
#
# M1 是本轮修掉的真缺陷：getdents64 号表写 217→217，
# 而 ARM64 的 217 是 add_key。它**只在 ARM64 端暴露** ——
# 只跑 x86 的测试永远发现不了，这正是两端都要跑的原因。

set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
mkdir -p build

MO2X=tools/mo2x.mo
PKG=examples/pkgmgr.mo
cp -f "$MO2X" build/pkgmgrmut_mo2x.bak
cp -f "$PKG"  build/pkgmgrmut_pkg.bak

restore() {
    cp -f build/pkgmgrmut_mo2x.bak "$MO2X"
    cp -f build/pkgmgrmut_pkg.bak  "$PKG"
    # 必须强制重建：cp 与上次的构建可能落在同一秒，make 只比时间戳会跳过，
    # 于是测的是**上一个变异**的产物（v1.135 记过，症状是同一组变异
    # 两轮跑出不同结论）。
    rm -f bin/mo2x
    make bin/mo2x >/dev/null 2>&1
}
trap restore EXIT INT TERM

rebuild() { rm -f bin/mo2x; make bin/mo2x >/dev/null 2>&1; }

# 应用一次替换（Python 精确子串，不用 sed 正则 —— 正则的空格/转义差异
# 会让"手工验证能匹配、脚本里却恒判未生效"）
apply() {   # apply <文件> <旧> <新> <变异名> [all]
    python3 - "$1" "$2" "$3" "$4" "${5:-one}" <<'PYEOF'
import sys
path, old, new, name, mode = sys.argv[1:6]
s = open(path).read()
c = s.count(old)
if c == 0:
    sys.stderr.write("锚点未找到：%s\n" % name)
    sys.exit(1)
# mode=all：同一段逻辑在程序里出现多次，不全部改掉就回不到缺陷状态
if c != 1 and mode != "all":
    sys.stderr.write("锚点不唯一(%d 处)：%s\n" % (c, name))
    sys.exit(1)
open(path, 'w').write(s.replace(old, new))
print("   已注入 %s（%d 处）" % (name, c))
PYEOF
}

echo "=== pkgmgr 变异验证 ==="

# ---- 基线 ----
rebuild
if bash tools/pkgmgrtest.sh >/tmp/pkgmgrmut_base.log 2>&1; then
    echo "  ✓ 基线通过（$(tail -1 /tmp/pkgmgrmut_base.log)）"
else
    echo "  ✗ 基线就没通过 —— 后面的变异全部无意义"
    tail -20 /tmp/pkgmgrmut_base.log
    exit 1
fi

CAP=0
TOT=0

run_mut() {   # run_mut <名> <文件> <旧> <新> [all]
    TOT=$((TOT + 1))
    restore
    if ! apply "$2" "$3" "$4" "$1" "${5:-one}"; then
        echo "  ✗ $1 无法注入"
        return
    fi
    if [ "$2" = "$MO2X" ]; then rebuild; fi
    if bash tools/pkgmgrtest.sh >/tmp/pkgmgrmut_$1.log 2>&1; then
        echo "  ✗ $1 未被捕获（测试仍然全绿 = 判据没验到它）"
    else
        echo "  ✓ $1 被捕获（$(grep -c '✗' /tmp/pkgmgrmut_$1.log) 项变红）"
        CAP=$((CAP + 1))
    fi
}

# M1：getdents64 退回"原样透传 x86 号" —— 本轮修掉的真缺陷
run_mut M1 "$MO2X" \
    "if n == 217 { return 61;  }   # getdents64" \
    "if n == 217 { return 217; }   # getdents64"

# M2：cfs 后端不输出内存原语宏 —— load8/store8 变成 undeclared
run_mut M2 "$MO2X" \
    "    emit_mem_macros();

    line(\"/* 完全不依赖 libc" \
    "    line(\"/* 完全不依赖 libc"

# M3：删目录的号表项去掉 —— ARM64 上 rmdir 无法翻译
run_mut M3 "$MO2X" \
    "if n == 84  { FS_ATINS = 1; return 35;  }   # rmdir  → unlinkat" \
    "/* M3 已移除 rmdir 映射 */"

# M4：VM 的 MUL 退化成 ADD —— 两个包跑出 13 / 44，不再是 42 / 84
run_mut M4 "$PKG" \
    "                    VS[sp - 2] = VS[sp - 2] * VS[sp - 1];" \
    "                    VS[sp - 2] = VS[sp - 2] + VS[sp - 1];"

# M5：忘记跳过 \".\" 与 \"..\" —— 列目录会多出两个
run_mut M5 "$PKG" \
    "        if load8(&DB + off + 19) == 46 {" \
    "        if 0 == 1 {" \
    all

restore
echo
echo "捕获 $CAP / $TOT 个变异"
[ "$CAP" -eq "$TOT" ] || exit 1
exit 0
