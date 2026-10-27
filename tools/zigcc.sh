#!/bin/bash
# zigcc —— 统一获取 zig C 编译器
#
#   ZIGCC=$(bash tools/zigcc.sh) || exit 1
#
# 各系统级目标（内核 / Windows / 安卓 / 交叉 / WASM）都靠 zig 提供
# 交叉编译与各平台的 libc。zig 不在系统包管理器里时，用 pip 装。
#
# 为什么要这一层：脚本直接写 `python3 -m ziglang cc` 时，
# zig 缺失的报错是 "No module named ziglang" —— 完全看不出该做什么。
# 统一在这里检测并给出明确指引（或直接装好）。

have_zig() {
    python3 -m ziglang version >/dev/null 2>&1
}

if have_zig; then
    echo "python3 -m ziglang cc"
    exit 0
fi

# 尝试自动安装
if command -v pip3 >/dev/null 2>&1; then P=pip3; else P=pip; fi
echo "zig 未安装，正在通过 pip 获取（zig 提供交叉编译与 libc）..." >&2
$P install ziglang >/dev/null 2>&1

if have_zig; then
    echo "python3 -m ziglang cc"
    exit 0
fi

# 无 zig 时的兜底：系统交叉 gcc。zigcc.sh 的调用方约定是"打印一条 cc 命令"，
# 这里按目标 triplet 分发到对应的交叉编译器（实测 aarch64 与 x86_64）。
# 兜底条件：$1 = 目标 triplet（android_native.sh / cross.sh 传 aarch64-linux-musl 等）。
if [ -n "$1" ]; then
    case "$1" in
        aarch64*)
            command -v aarch64-linux-gnu-gcc >/dev/null 2>&1 && { echo "aarch64-linux-gnu-gcc"; exit 0; } ;;
        x86_64*|amd64*)
            command -v gcc >/dev/null 2>&1 && { echo "gcc"; exit 0; } ;;
    esac
fi

echo "" >&2
echo "✗ 无法获取 zig。系统级目标（内核/Windows/安卓/交叉/WASM）需要它。" >&2
echo "  手动安装： pip install ziglang" >&2
echo "  或下载：   https://ziglang.org/download/" >&2
exit 1
