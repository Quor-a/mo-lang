#!/bin/bash
# fenwtest —— Fenwick 树（BIT）端到端验证
#
# tests/150_fenw.mo 已经被 make test 跑到，但那里只报一个总数。
# 本脚本把它单独拎出来跑，并且**额外**要求：
#   · 退出码必须为 0
#   · 汇总行必须是 "ran 24, failed 0"（断言条数写死）
#     —— 少了说明断言被删/被跳过，多了说明有人新增却没同步这里。
#      这是防"测试静默缩水"的守卫，不是装饰。
#   · 输出里必须含结构断言的实测数字

HERE="$(cd "$(dirname "$0")/.." && pwd)"
cd "$HERE" || exit 1

rm -rf /tmp/mot150t && mkdir -p /tmp/mot150t
cp "$HERE"/lib/*.mo /tmp/mot150t/
cp "$HERE"/tests/150_fenw.mo /tmp/mot150t/test.mo

if ! ( cd /tmp/mot150t && "$HERE"/bin/moc test.mo out.elf ) >/dev/null 2>&1; then
    echo "✗ fenwtest 编译失败"
    exit 1
fi
chmod +x /tmp/mot150t/out.elf 2>/dev/null

( cd /tmp/mot150t && timeout 60 ./out.elf ) >/tmp/mot150t/o.txt 2>&1
rc=$?

cat /tmp/mot150t/o.txt

if [ "$rc" != "0" ]; then
    echo "✗ fenwtest 失败（退出码 $rc）"
    exit 1
fi

if ! grep -q '^ran 24, failed 0$' /tmp/mot150t/o.txt; then
    echo "✗ fenwtest：汇总行不是 'ran 24, failed 0'（断言条数变了？）"
    exit 1
fi

if ! grep -q '^n1=' /tmp/mot150t/o.txt; then
    echo "✗ fenwtest：缺少实测数字输出"
    exit 1
fi

echo "✓ fenwtest 通过（24 项断言）"
exit 0
