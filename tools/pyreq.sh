#!/bin/bash
# pyreq —— 统一获取运行时验证所需的 Python 包
#
#   bash tools/pyreq.sh unicorn
#
# 为什么要装到 /data/workspace/pylibs 而不是系统目录：
# 沙盒/容器环境会被重置，`pip install` 明明报成功，下一次调用包就不见了
# （实测反复出现）。所以统一装到工作区下的持久目录，再把它加进
# PYTHONPATH —— 这样不受系统目录被重置的影响。
#
# 与 tools/zigcc.sh 是同一套思路：外部工具统一在一处检测与获取。
set +e
PKG=${1:-unicorn}

# 用户可覆盖：MO_PYLIBS=/somewhere bash tools/pyreq.sh unicorn
LIBS=${MO_PYLIBS:-/data/workspace/pylibs}

have() {
    PYTHONPATH="$LIBS${PYTHONPATH:+:$PYTHONPATH}" python3 -c "import $PKG" >/dev/null 2>&1
}

if have; then
    export PYTHONPATH="$LIBS${PYTHONPATH:+:$PYTHONPATH}"
    echo "ok: $PKG 可用（$LIBS）"
    exit 0
fi

mkdir -p "$LIBS" 2>/dev/null
if command -v pip3 >/dev/null 2>&1; then P=pip3; else P=pip; fi
echo "$PKG 未安装，正在安装到 $LIBS ..." >&2
$P install --target "$LIBS" "$PKG" >/dev/null 2>&1

if have; then
    export PYTHONPATH="$LIBS${PYTHONPATH:+:$PYTHONPATH}"
    echo "ok: $PKG 已安装（$LIBS）"
    exit 0
fi

echo "" >&2
echo "✗ 无法获取 $PKG。运行时验证（内核 / UEFI / ARM64 / RISC-V / s390x）需要它。" >&2
echo "  手动安装： pip install --target $LIBS $PKG" >&2
echo "" >&2
echo "  没有它的代价：这些目标只能验证到"产物结构正确"，不能验证真的能启动。" >&2
exit 1
