#!/bin/bash
# scopetest —— 结构化并发（nursery）端到端验证
#
# 被测：lib/scope.mo（经 examples/structconc.mo 的 `import "scope.mo"`）。
# 这里显式写出库名 —— projcheck 第 3 项按 "scope.mo" 字符串扫引用，
# 只写 `cp lib/*.mo` 会让它判成"无测试覆盖"。
#
# 必须走 molink + libc：ucontext / pthread 在 libc 里。
#
# 判据不是"有没有崩"，而是**具体数字**：
#   · 不 join 就读到半成品  → sum 必须精确等于 8000
#   · 取消没有传播          → iter 必须远小于 full
#   · 错误被外层吞掉        → oerr 必须等于 ierr
#   · 协程逃逸成孤儿        → close 之后再等 200ms，值不许再变
HERE=$(cd "$(dirname "$0")/.." && pwd)
MOC="$HERE/bin/moc"; LINK="$HERE/tools/molink.sh"
TMP="$HERE/build/scopetest_tmp"
rm -rf $TMP && mkdir -p $TMP/lib
cp "$HERE"/lib/*.mo $TMP/lib/
cp "$HERE"/examples/structconc.mo $TMP/
cd $TMP
PASS=0; FAIL=0
ck() { if [ "$1" = "$2" ]; then PASS=$((PASS+1)); echo "  ✓ $3"; else FAIL=$((FAIL+1)); echo "  ✗ $3 (得到 '$1' 想要 '$2')"; fi; }
cklt() { if [ "$1" -lt "$2" ] 2>/dev/null; then PASS=$((PASS+1)); echo "  ✓ $3 (得到 $1 < $2)"; else FAIL=$((FAIL+1)); echo "  ✗ $3 (得到 $1 不 < $2)"; fi; }

$MOC structconc.mo -c -o structconc.o || { echo "✗ 编译失败"; exit 1; }
bash "$LINK" structconc.o -o structconc >/dev/null || { echo "✗ 链接失败"; exit 1; }
# 🔴 必须 -k：光有 timeout 只杀 timeout 自己那一层，孙进程 ./structconc 会活下来，
#    继续占 CPU，把**下一次**运行的调度时序拖歪（2 核机器上表现为 close 走到
#    超时、SC_HANG 被误置）。本轮实测：强杀后残留一个 structconc，紧接着的
#    基线立刻 31/1，而干净环境下连跑 3 次都是 32/0。
timeout -k 5 180 ./structconc > out.txt 2>&1
RC=$?
ck "$RC" "0" "程序正常退出"

v() { grep -oE "^$1=[0-9-]+" out.txt | tail -1 | cut -d= -f2; }
# 场景 C 与 D 都打印 ierr/oerr：第一次出现是 C，最后一次是 D。
# 用 tail -1 取会把 D 的值当成 C 的 —— 两个场景共用变量名，解析必须分开。
v1() { grep -oE "^$1=[0-9-]+" out.txt | head -1 | cut -d= -f2; }

echo "== A. join =="
ck "$(v sum)"  "8000" "join 之后读到完整值（4×2000）"
cklt "$(v pre)" "8000" "join 之前读到的是半成品 —— join 不是装饰"
ck "$(v post1)" "$(v post2)" "close 之后再等 200ms 值不变 —— 没有协程逃逸成孤儿"

echo "== B. 取消传播 =="
# 🔴 判据是"每个兄弟**最终都收到了取消**"，不是"兄弟提前停了多少"。
#    后者由调度时序支配：兄弟完全可能在取消到达之前就跑完（实测 iter
#    在 2 / 14 / 54 / 33022 / 130 之间跳），不可重复。
ckge() { if [ "$1" -ge "$2" ] 2>/dev/null; then PASS=$((PASS+1)); echo "  ✓ $3 (得到 $1 >= $2)"; else FAIL=$((FAIL+1)); echo "  ✗ $3 (得到 $1 不 >= $2)"; fi; }
cs() { grep -oE "^iter$1=[0-9]+ cseen=[0-9-]+" out.txt | grep -oE "cseen=[0-9-]+" | cut -d= -f2; }
ckge "$(cs 1)" "0" "兄弟 1 收到了取消（cseen >= 0）"
ckge "$(cs 2)" "0" "兄弟 2 收到了取消（cseen >= 0）"
ckge "$(cs 3)" "0" "兄弟 3 收到了取消（cseen >= 0）"
ck "$(cs 0)" "-1" "失败者自己不进取消观测（它没被取消，是它发起的）"
cklt "$(v iter)" "400000" "兄弟提前停了（完整跑完是 $(v full)）"
ck "$(v eb)" "42" "close 返回首个错误码"

echo "== C. 嵌套 =="
ck "$(v gsum)" "3" "内层 scope 的 3 个孙协程全部跑完"
ck "$(v1 ierr)" "0" "内层 close 无错（场景 C）"
ck "$(v1 oerr)" "0" "外层 close 无错（场景 C）"

echo "== D. 错误冒泡 =="
# 场景 D 会覆盖 ierr/oerr，取最后一次
ck "$(v ierr)" "77" "内层 close 拿到 77（场景 D）"
ck "$(v oerr)" "77" "**外层** close 也拿到 77 —— 内层失败没被吞掉"

echo "== E. 协作式 channel =="
ck "$(v gn)" "6" "收到全部 6 个值"
ck "$(v g0)" "100" "第一个值正确（FIFO）"
ck "$(v g5)" "105" "最后一个值正确"

echo "== F. 被测 scope ≠ 0 =="
ck "$(v fs)" "1" "被测 scope 是 1（dummy 占掉了 0）—— 未登记的默认值不再巧合命中"
ck "$(v fnch)" "100" "spawn 了 64 个空体子协程"
ck "$(v ferr)" "0" "10 轮全部 close 无错 —— 没有子协程在登记前跑完"

echo "== G. 取消穿透嵌套 =="
ckge "$(v gseen)" "0" "**孙协程**看到了取消 —— 取消穿透了内层 scope"
cklt "$(v git)" "200000" "孙协程提前停了（没跑满 200000）"
ck "$(v derr)" "55" "外层 close 拿到 55"

echo "== H. 登记必须先于启动（交错注入）=="
ck "$(v hhold)" "1" "持锁者就位（交错确实被注入）"
ck "$(v hfail)" "0" "没有等不到持锁者"
ck "$(v herr)"  "0" "登记被锁卡住 100ms 后 close 仍无错"

echo "== 诊断 =="
ck "$(v open)"   "0" "没有未关闭的 scope"
ck "$(v orphan)" "0" "没有 spawn 到已关闭 scope"
ck "$(v hang)"   "0" "没有 close 超时"
ck "$(v ncancel)" "3" "取消计数 = 3（B / D / G 各一次）"
ck "$(v dead)"   "0" "调度器没判定死锁"

echo
echo "通过 $PASS / 失败 $FAIL"
[ $FAIL -eq 0 ]
