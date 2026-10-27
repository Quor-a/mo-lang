#!/bin/bash
# sketchtest —— Bloom / CMS 端到端验证（打印实测数字）
#
# 与 make test 的区别：make test 只看退出码，这里把实测数字打出来，
# 供 docs/sketch.md 引用。判据仍是退出码 0。
#
# ⚠️ 不要写成 `out=$(cmd | tail -1); rc=$?` ——
#    $? 取的是 tail 的退出码，恒 0，于是"失败"永远显示成"通过"
#    （v1.132 在 lfmut 里栽过，此处显式避开）。

HERE="$(cd "$(dirname "$0")/.." && pwd)"
cd "$HERE" || exit 1

rm -rf /tmp/mot && mkdir -p /tmp/mot
cp "$HERE"/lib/*.mo /tmp/mot/
cp "$HERE"/tests/145_sketch.mo /tmp/mot/test.mo

( cd /tmp/mot && "$HERE"/bin/moc test.mo out.elf ) || { echo "编译失败"; exit 1; }
chmod +x /tmp/mot/out.elf 2>/dev/null

( cd /tmp/mot && ./out.elf )
rc=$?

echo "sketchtest: rc=$rc"
[ "$rc" = "0" ]
