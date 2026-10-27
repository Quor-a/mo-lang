#!/bin/bash
# hhtest —— Heavy Hitters（Misra-Gries + Space-Saving）端到端验证
#
# tests/152_hh.mo 已经被 make test 跑到，但那里只报一个总数。
# 本脚本把它单独拎出来跑，并且**额外**要求：
#   · 退出码必须为 0
#   · 汇总行必须是 "ran 45, failed 0"（条数写死）
#     —— 少了说明断言被删/被跳过，多了说明有人新增却没同步这里。
#       这是防"测试静默缩水"的守卫，不是装饰。
#   · 输出里必须含实测数字（N= / mg_dec= / clamp[）
#   · **夹逼必须真的成立**：解析 clamp 行，逐条核对 mg ≤ true ≤ ss
#     —— 测试内部已经查过，这里用 shell 独立再查一遍，
#        防的是"测试自己算错了却自我一致"。

HERE="$(cd "$(dirname "$0")/.." && pwd)"
cd "$HERE" || exit 1

rm -rf /tmp/mot152t && mkdir -p /tmp/mot152t
cp "$HERE"/lib/*.mo /tmp/mot152t/
cp "$HERE"/tests/152_hh.mo /tmp/mot152t/test.mo
rm -f /tmp/mot152t/out.elf

if ! ( cd /tmp/mot152t && "$HERE"/bin/moc test.mo out.elf ) >/dev/null 2>&1; then
    echo "✗ hhtest 编译失败"
    exit 1
fi
chmod +x /tmp/mot152t/out.elf 2>/dev/null

( cd /tmp/mot152t && timeout 60 ./out.elf ) >/tmp/mot152t/o.txt 2>&1
rc=$?

cat /tmp/mot152t/o.txt

if [ "$rc" != "0" ]; then
    echo "✗ hhtest 失败（退出码 $rc）"
    exit 1
fi

if ! grep -q '^ran 45, failed 0$' /tmp/mot152t/o.txt; then
    echo "✗ hhtest：汇总行不是 'ran 45, failed 0'（断言条数变了？）"
    exit 1
fi

for key in '^N=' 'mg_dec=' 'ss_repl=' 'clamp\[1\]'; do
    if ! grep -q "$key" /tmp/mot152t/o.txt; then
        echo "✗ hhtest：缺少实测数字输出（$key）"
        exit 1
    fi
done

# ── 独立复核夹逼：mg ≤ true ≤ ss ──────────────────────────
python3 - <<'PY'
import re, sys
txt = open('/tmp/mot152t/o.txt').read()
rows = re.findall(r'clamp\[(\d+)\] mg=(-?\d+) true=(-?\d+) ss=(-?\d+) sserr=(-?\d+)', txt)
if len(rows) < 3:
    print("✗ hhtest：clamp 行不足 3 条（实测输出变了？）")
    sys.exit(1)
bad = 0
for idx, mg, tru, ss, er in rows:
    mg, tru, ss, er = int(mg), int(tru), int(ss), int(er)
    if not (mg <= tru <= ss):
        print("✗ hhtest：夹逼被破坏 clamp[%s] mg=%d true=%d ss=%d" % (idx, mg, tru, ss))
        bad += 1
    if ss - er > tru:
        print("✗ hhtest：ss err 界被破坏 clamp[%s] ss=%d err=%d true=%d" % (idx, ss, er, tru))
        bad += 1
if bad:
    sys.exit(1)
print("✓ hhtest：%d 条夹逼独立复核通过" % len(rows))
PY
[ $? -ne 0 ] && exit 1

echo "✓ hhtest 通过（45 项断言）"
exit 0
