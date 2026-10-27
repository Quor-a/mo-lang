#!/bin/bash
# iototest —— 带超时的异步 I/O（select { I/O 就绪, 定时器 }）端到端验证
#
# 跑 examples/httpto.mo：6 个快客户端 + 6 个慢客户端（连上后睡 3 秒不发），
# 服务端用 ioto_recv(fd, buf, n, 400) 读请求。
#
# 判据不是"有没有崩"，而是**具体数字**。最有信息量的三条：
#   · cncl = 6 —— I/O 就绪时成功取消掉 6 个定时器。cancel 生效的硬证据：
#     删掉 tm_cancel 这一行它会变成 0。
#   · fired = 6 而不是 12 —— 12 次 arm 里只有 6 次真正触发，另外 6 次
#     被 cancel 拦住了。这条单独就能证明取消不是空转。
#   · nto = 6 且 toms ∈ [400, 492] —— 慢连接确实在 deadline 被掐断，
#     而且**不早于** deadline（时间轮量化基准是上一个 tick，不补零头
#     就会提前最多一个 tick）。
#
# 为什么必须跑真网络：超时是时序行为，单元测试里"等一会儿"造不出
# "连上但不发"这种形状。
HERE=$(cd "$(dirname "$0")/.." && pwd)
MOC="$HERE/bin/moc"; LINK="$HERE/tools/molink.sh"
TMP=/tmp/moioto
rm -rf $TMP && mkdir -p $TMP/lib
cp "$HERE"/lib/*.mo $TMP/lib/
cp "$HERE"/examples/httpto.mo $TMP/
cd $TMP
PASS=0; FAIL=0
ck() { if [ "$1" = "$2" ]; then PASS=$((PASS+1)); echo "  ✓ $3"; else FAIL=$((FAIL+1)); echo "  ✗ $3 (得到 '$1' 想要 '$2')"; fi; }
ckge() { if [ "$1" -ge "$2" ] 2>/dev/null; then PASS=$((PASS+1)); echo "  ✓ $3 ($1 >= $2)"; else FAIL=$((FAIL+1)); echo "  ✗ $3 (得到 '$1' 想要 >= $2')"; fi; }
ckle() { if [ "$1" -le "$2" ] 2>/dev/null; then PASS=$((PASS+1)); echo "  ✓ $3 ($1 <= $2)"; else FAIL=$((FAIL+1)); echo "  ✗ $3 (得到 '$1' 想要 <= $2')"; fi; }

# 守卫：示例必须真的 import "ioto.mo"。哪天这行被删，示例会退化成不带超时
# 的普通异步 I/O，而下面 21 项断言**照样全绿** —— 那就不是在测 ioto 了。
grep -q '"ioto.mo"' httpto.mo || { echo "  ✗ 示例没有 import ioto.mo"; exit 1; }

$MOC httpto.mo -c httpto.o >/dev/null 2>err.txt || { echo "  ✗ 编译失败"; cat err.txt; exit 1; }
bash $LINK httpto.o -o httpto >/dev/null 2>&1 || { echo "  ✗ 链接失败"; exit 1; }
timeout 120 ./httpto > out.txt 2>&1; RC=$?
if [ $RC -ne 0 ]; then echo "  ✗ 运行失败 rc=$RC"; cat out.txt; exit 1; fi
cat out.txt

g() { grep -oE "(^| )$1=[0-9-]+" out.txt | head -1 | tr -d ' ' | cut -d= -f2; }

echo "  连接与响应："
ck "$(g nconn)" "12" "12 个连接全部被 accept"
ck "$(g nok)" "6" "6 个快客户端全部拿到响应"
ck "$(g nto)" "6" "6 个慢客户端全部被超时掐断"
ckge "$(g cfsend)" "1" "慢客户端确实写不进去了（连接已被服务端关闭）"

echo "  超时精度（时间轮量化）："
ckge "$(g toms)" "400" "超时不早于 deadline 400ms（不补零头会提前最多一个 tick）"
# 上界留到 400+8·tick+60：机器负载会让定时器线程晚醒，太紧会偶发红灯
# （实测 17 次里出现过一次）。下界 400 才是核心 —— 它抓的是"提前触发"。
ckle "$(g toms)" "588" "超时不晚于 400+8·tick+60（负载下留余量）"

echo "  取消是否真的生效（本轮核心）："
ckge "$(g cncl)" "6" "I/O 就绪分支成功取消 >=6 个定时器（删掉 tm_cancel 会变 0）"
ck "$(g fired)" "6" "12 次 arm 只有 6 次真正触发 —— 另外 6 次被 cancel 拦住"
ck "$(g late)" "6" "超时分支的 cancel 迟了一步（已触发），符合预期"
ckge "$(g iok)" "6" "I/O 就绪分支命中 >=6 次（TCP 分片会让它更多）"
ck "$(g ito)" "6" "超时分支命中 6 次"

echo "  无幽灵值 / 无泄漏："
ck "$(g tdrn)" "0" "定时器 channel 归还时没有残留值（有则为幽灵超时）"
ck "$(g idrn)" "0" "I/O channel 归还时没有残留值（有则为假就绪）"
ck "$(g iovf)" "0" "I/O channel 池没耗尽"
ckle "$(g chnc)" "20" "channel 总数有界（回收池生效；不回收会随 arm 次数增长，M4 变体会突破这个上界）"
ck "$(g miss)" "0" "定时器投递没有失败"
ck "$(g aion)" "1" "结束时只剩 acceptor 的监听 fd 在等（业务 fd 槽必须为 0；超时路径不 disarm 就会残留 6 个）"

echo "  线程健康："
ck "$(g iperr)" "0" "ioto 没有内部错误"
ck "$(g aperr)" "0" "aio 没有内部错误"
ck "$(g qovf)" "0" "运行队列没溢出"
ck "$(g dead)" "0" "调度器没判定死锁"

echo
echo "通过 $PASS / 失败 $FAIL"
[ $FAIL -eq 0 ]
