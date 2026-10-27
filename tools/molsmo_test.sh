#!/bin/bash
# molsmo_test —— 墨语言版 LSP 服务器（tools/mols.mo）的验证
#
# 为什么单独一个脚本：
#   lsptest.py 默认跑 tools/mols.py（Python 版）。墨语言版要先编译成
#   bin/mols，再用 MOLS 环境变量指过去，跑**同一套** 27 项断言 ——
#   两份实现共用一份测试，才谈得上"等价"。
#
# 为什么必须在 /tmp 下编译：
#   moc 的 import 解析依赖 cwd，直接编 tools/mols.mo 会因为找不到
#   lib/ 而失败。
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"

rm -rf /tmp/molsbuild && mkdir -p /tmp/molsbuild
cp "$HERE"/lib/*.mo /tmp/molsbuild/ || exit 1
cp "$HERE"/tools/mols.mo /tmp/molsbuild/test.mo || exit 1
( cd /tmp/molsbuild && "$HERE/bin/moc" ) || { echo "✗ mols.mo 编译失败"; exit 1; }
cp /tmp/molsbuild/out.elf "$HERE/bin/mols" || exit 1
chmod +x "$HERE/bin/mols"

echo "== 墨语言版 mols（bin/mols）=="
MOLS="$HERE/bin/mols" python3 "$HERE/tools/lsptest.py"
rc=$?
echo "== Python 版 mols.py（对照）=="
python3 "$HERE/tools/lsptest.py" | tail -1
exit $rc
