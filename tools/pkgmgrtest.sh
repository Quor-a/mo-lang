#!/bin/bash
# pkgmgrtest —— 包管理器在**安卓（ARM64）与 x86-64 两端**的端到端验证
#
#   make pkgmgrtest
#
# 验什么
# ------
# examples/pkgmgr.mo 是一个自带运行环境的包管理器：
#   建包根 → 装两个包（各带字节码）→ 列目录 → 读清单 → **执行包** → 卸一个 → 再列
#
# 判据不靠程序自证：所有数字都打到 stdout，由本脚本与**期望值**比对。
# 两个包跑出的数字刻意不同（42 / 84），这样才能区分"VM 真执行了"
# 和"碰巧打印了一个常量"。
#
# 两端都跑，是因为本轮修掉的缺陷正是**只在一端暴露**的那一类：
# getdents64 号表此前写 217→217，在 x86 上恰好正确，
# 在 ARM64 上 217 是 add_key —— 只跑 x86 永远发现不了。

set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

PASS=0
FAIL=0

ck() {   # ck <描述> <实际> <期望>
    if [ "$2" = "$3" ]; then
        echo "  ✓ $1 ($2)"
        PASS=$((PASS + 1))
    else
        echo "  ✗ $1 (得到 '$2' 想要 '$3')"
        FAIL=$((FAIL + 1))
    fi
}

# 从输出里抠出某个键的值：行形如 "[6] run demo      out=42"
val() { echo "$1" | grep -F "$2" | head -1 | sed 's/.*=//' | tr -d ' \r'; }

run_one() {   # run_one <架构名> <ARCH> <是否用模拟器>
    local tag=$1 arch=$2 sim=$3
    local out rc

    rm -rf /tmp/mo_pkgs            # 真机端会真建目录；不清理第二次必 EEXIST
    local bin=/tmp/pkgmgr_$tag
    rm -f "$bin"
    if ! ARCH=$arch bash tools/android_native.sh examples/pkgmgr.mo "$bin" \
            >/tmp/pkgmgr_build_$tag.log 2>&1; then
        echo "  ✗ $tag 构建失败"
        tail -3 /tmp/pkgmgr_build_$tag.log
        FAIL=$((FAIL + 2))
        return
    fi

    if [ "$sim" = "yes" ]; then
        out=$(python3 tools/armrun.py "$bin" 2>&1)
        rc=$?
    else
        out=$("$bin" 2>&1)
        rc=$?
    fi

    echo "[$tag] 退出码=$rc"
    ck "$tag 退出码" "$rc" "0"
    ck "$tag pkg ok"        "$(val "$out" 'pkg ok = ')"       "1"
    ck "$tag 装包后列目录"  "$(val "$out" '[4] list count')"  "2"
    ck "$tag 清单版本"      "$(val "$out" '[5] info demo')"   "1.0.0"
    ck "$tag 执行 demo"     "$(val "$out" '[6] run demo ')"   "42"
    ck "$tag 执行 demo2"    "$(val "$out" '[6] run demo2')"   "84"
    ck "$tag 卸载 ret"      "$(val "$out" '[7] remove demo')" "0"
    ck "$tag 卸载后列目录"  "$(val "$out" '[8] list after')"  "1"
    # VM 边界：损坏 / 恶意的包必须响亮失败（未修复时这五项全部静默返回 0）
    ck "$tag VM 合法包"     "$(val "$out" '[9a] legal')"      "42"
    ck "$tag ADD 下溢"      "$(val "$out" '[9b] underflow')"  "-2"
    ck "$tag PRINT 下溢"    "$(val "$out" '[9c] print uf')"   "-2"
    ck "$tag 立即数截断"    "$(val "$out" '[9d] trunc')"      "-4"
    ck "$tag 栈上溢"        "$(val "$out" '[9e] overflow')"   "-3"
    ck "$tag VM 边界总"     "$(val "$out" '[9] vmguard')"     "1"
    # 卸载后必须**只剩 demo2**：既不能两个都在（没删掉），也不能一个不剩（删过头）。
    # 取 [8] 行的**上一行**（包名行的打印在计数行之前），精确比对整行 ——
    # 早先用 tail -N 抓取，会把 "[7] remove demo" 那行一起框进来，
    # 而它里面也有 "demo"，于是 -w 判据失效。
    local left
    left=$(echo "$out" | grep -B1 '\[8\] list after' | head -1 | sed 's/[[:space:]]*$//')
    ck "$tag 卸载后剩余包" "$left" "demo2"
}

echo "=== 包管理器端到端验证（ARM64 模拟器 / x86-64 真机）==="
run_one arm64 aarch64 yes
run_one x86   x86_64  no

echo
echo "通过 $PASS 项，失败 $FAIL 项"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
