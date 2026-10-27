#!/bin/bash
# segtest —— 线段树 + 懒标记端到端验证
#
# tests/151_seg.mo 已经被 make test 跑到，但那里只报一个总数。
# 本脚本把它单独拎出来跑，并且**额外**要求：
#   · 退出码必须为 0
#   · 汇总行必须是 "ran 150, failed 0"（断言条数写死）
#     —— 少了说明断言被删/被跳过，多了说明有人新增却没同步这里。
#      这是防"测试静默缩水"的守卫，不是装饰。
#   · 输出里必须含实测数字

HERE="$(cd "$(dirname "$0")/.." && pwd)"
cd "$HERE" || exit 1

rm -rf /tmp/mot151t && mkdir -p /tmp/mot151t
cp "$HERE"/lib/*.mo /tmp/mot151t/
cp "$HERE"/tests/151_seg.mo /tmp/mot151t/test.mo
rm -f /tmp/mot151t/out.elf

if ! ( cd /tmp/mot151t && "$HERE"/bin/moc test.mo out.elf ) >/dev/null 2>&1; then
    echo "✗ segtest 编译失败"
    exit 1
fi
chmod +x /tmp/mot151t/out.elf 2>/dev/null

( cd /tmp/mot151t && timeout 60 ./out.elf ) >/tmp/mot151t/o.txt 2>&1
rc=$?

cat /tmp/mot151t/o.txt

if [ "$rc" != "0" ]; then
    echo "✗ segtest 失败（退出码 $rc）"
    exit 1
fi

if ! grep -q '^ran 150, failed 0$' /tmp/mot151t/o.txt; then
    echo "✗ segtest：汇总行不是 'ran 150, failed 0'（断言条数变了？）"
    exit 1
fi

if ! grep -q '^cmps=' /tmp/mot151t/o.txt; then
    echo "✗ segtest：缺少实测数字输出"
    exit 1
fi

echo "✓ segtest 通过（150 项断言）"
exit 0
