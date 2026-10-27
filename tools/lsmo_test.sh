#!/bin/bash
# lsmo_test —— 墨语言版 LSP **驱动**（tools/lsptest.mo）的验证
#
# 为什么单独一个脚本：
#   服务器 mols 与驱动 lsptest 都已是墨语言写的，但**编译它们需要 moc**，
#   而 moc 的 import 解析依赖 cwd，所以必须各自在 /tmp 下平铺 lib 再编。
#
# 交叉验证：
#   墨语言驱动 spawn 起 bin/mols 跑 27 项；Python 驱动 lsptest.py 用
#   MOLS 环境变量指到**同一个** bin/mols 再跑一遍 —— 两个独立客户端
#   对同一个服务器得出一致结论，才谈得上"等价"。
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"

# 1) 编译服务器 bin/mols
rm -rf /tmp/molsbuild && mkdir -p /tmp/molsbuild
cp "$HERE"/lib/*.mo /tmp/molsbuild/ || exit 1
cp "$HERE"/tools/mols.mo /tmp/molsbuild/test.mo || exit 1
( cd /tmp/molsbuild && "$HERE/bin/moc" ) || { echo "✗ mols.mo 编译失败"; exit 1; }
cp /tmp/molsbuild/out.elf "$HERE/bin/mols" || exit 1
chmod +x "$HERE/bin/mols"

# 2) 编译驱动 bin/lsptest
rm -rf /tmp/lsptestbuild && mkdir -p /tmp/lsptestbuild
cp "$HERE"/lib/*.mo /tmp/lsptestbuild/ || exit 1
cp "$HERE"/tools/lsptest.mo /tmp/lsptestbuild/test.mo || exit 1
( cd /tmp/lsptestbuild && "$HERE/bin/moc" ) || { echo "✗ lsptest.mo 编译失败"; exit 1; }
cp /tmp/lsptestbuild/out.elf "$HERE/bin/lsptest" || exit 1
chmod +x "$HERE/bin/lsptest"

echo "== 墨语言驱动 bin/lsptest（spawn bin/mols）=="
"$HERE/bin/lsptest" "$HERE/bin/mols" "$HERE"
rc=$?
echo "== Python 驱动 lsptest.py（对照，同一服务器）=="
MOLS="$HERE/bin/mols" python3 "$HERE/tools/lsptest.py" | tail -1
exit $rc
