#!/bin/bash
# iotomut —— 带超时 I/O 的变异验证
#
# 只跑一遍 iototest 全绿证明不了任何事。三条最关键的断言
# （cncl=6 / fired=6 / nto=6）必须各自有一个"对应的坏版本"会变红，
# 否则它们可能只是在比两个恒等的数。
#
# 变异脚本自身的纪律（本项目已栽过三次）：
#   · 每次变异都从**原始副本**重新拷贝，不依赖上一次是否还原成功
#   · trap 覆盖 EXIT/INT/TERM —— 上次被中断后源码停在变异态，基线全红
#   · 收尾用 diff 逐字节核对，并保留备份副本
HERE=$(cd "$(dirname "$0")/.." && pwd)
T="$HERE/tools/iototest.sh"
SRC="$HERE/lib/ioto.mo"
BK=/tmp/iotomutbk
OUT=/tmp/iotomutout.txt
rm -rf $BK && mkdir -p $BK
cp "$SRC" "$BK/orig.mo"
restore() { cp "$BK/orig.mo" "$SRC"; }
trap restore EXIT INT TERM

run() { timeout 400 bash "$T" > $OUT 2>&1; echo $?; }
summary() { grep -E "^通过" $OUT | tail -1; }
val() { grep -oE "(^| )$1=[0-9-]+" $OUT | head -1 | tr -d ' ' | cut -d= -f2; }

# 同上：确认被测的确实是 ioto.mo
grep -q '"ioto.mo"' "$HERE/examples/httpto.mo" || { echo "✗ 示例没有 import ioto.mo"; exit 1; }

echo "== 基线 =="
B=$(run)
echo "$(summary)  (rc=$B)  cncl=$(val cncl) fired=$(val fired) nto=$(val nto)"
if [ "$B" != "0" ]; then
  echo "✗ 基线就没过，变异无意义"
  echo "  若上一次是被强杀留下的变异态，用：cp $BK/orig.mo $SRC"
  tail -5 $OUT; exit 1
fi

mut1() { # 单处替换
    cp "$BK/orig.mo" "$SRC"
    python3 - "$SRC" "$3" "$4" "$5" <<'PY'
import sys
p,a,b,mode=sys.argv[1],sys.argv[2],sys.argv[3],sys.argv[4]
s=open(p).read()
n=s.count(a)
if mode=="all":
    if n<1:
        print("ANCHOR_MISS:%d"%n); sys.exit(1)
    open(p,'w').write(s.replace(a,b))
else:
    if n!=1:
        print("ANCHOR_MISS:%d"%n); sys.exit(1)
    open(p,'w').write(s.replace(a,b))
PY
    if [ $? -ne 0 ]; then echo "  ✗ $1 锚点未命中，变异未生效"; return 0; fi
    local r; r=$(run)
    if [ "$r" = "0" ]; then
        echo "  ✗ $1 $2 —— 未被捕获（测试对此无感）"
        echo "     $(summary)  cncl=$(val cncl) fired=$(val fired) nto=$(val nto)"
    else
        echo "  ✓ $1 $2 —— 被捕获"
        echo "     $(summary)  cncl=$(val cncl) fired=$(val fired) nto=$(val nto)"
        CAP=$((CAP+1))
    fi
}

CAP=0; TOT=0
mut() { TOT=$((TOT+1)); mut1 "$1" "$2" "$3" "$4" one; }
mutall() { TOT=$((TOT+1)); mut1 "$1" "$2" "$3" "$4" all; }

echo "== 变异 =="
mut M1 "不取消定时器（幽灵超时的源头）" \
    "    tm_cancel(t);" \
    "    tm_cancel(0 - 1);"
mutall M2 "等待的事件方向写反（读等成写）" \
    "w = ioto_waitfd(fd, 1, rem);" \
    "w = ioto_waitfd(fd, 4, rem);"
mutall M3 "channel 归还/取出都不排空（残留值 = 假就绪）" \
    "while chan_tryrecv(c) == 1 { IOTO_DRN = IOTO_DRN + 1; }" \
    "while 0 { IOTO_DRN = IOTO_DRN + 1; }"
# 记录性变异：不注销 fd。实测**常常不被捕获** —— 因为 aio_close 里本来
# 就会清槽，disarm 在当前调用模式下是防御性冗余。留着它是为了留下证据：
# "改了代码却没变红"本身也是信息，不该被悄悄删掉。
mut M5 "不注销 fd（aio_close 会兜住 —— 预期常不被捕获）" \
    "    aio_disarm(fd);
    tm_cancel(t);" \
    "    aio_disarm(0 - 1);
    tm_cancel(t);"
# 原 M4（超时当成就绪）**不被捕获**是有道理的：ioto_recv 会在 rem<=0 时
# 兜住并最终返回超时，行为等价。换成"池不回收"—— 它直接验证回收池是否生效。
mut M4 "channel 用不回收（池失效 → channel 总数无限增长）" \
    "    IOTO_PC[IOTO_PN] = c;
    IOTO_PN = IOTO_PN + 1;
    return 0;
}" \
    "    return 0;
}"

restore
if diff -q "$BK/orig.mo" "$SRC" >/dev/null; then echo "== 源码已还原（diff 逐字节一致） =="
else echo "✗ 还原失败！源码仍处在变异状态"; exit 1; fi
trap - EXIT INT TERM
echo "（原始副本保留在 $BK/orig.mo）"
echo "捕获 $CAP / $TOT"
[ $CAP -ge 3 ]   # M1/M2/M4 必须捕获；M3/M5 是记录性的
