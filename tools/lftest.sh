#!/bin/bash
# lftest —— 无锁数据结构（Treiber 栈 / Michael–Scott 队列 / 危险指针）端到端验证
#
# 必须走 molink + libc + libatomic：pthread 在 libc，CAS 符号在 libatomic。
#
# 判据不是"有没有崩"，而是**每一项都要给出具体数字**：
#   * 守恒：push 4000 个，drain 必须正好 4000，missing=0 dup=0
#     —— 漏/重都只表现为数字不对，不报错。
#   * ABA：受控交错下，有 tag 剩 3 个、无 tag 剩 2 个（丢了一个）
#     —— 两个数必须不同，否则说明 tag 根本没参与决策。
#   * UAF：不保护时读到 999（被复用覆盖），保护时仍是 3。
#
# ⚠ 守卫：示例必须真的 import "lf.mo"，否则退化成别的东西而本测试照样全绿。
HERE=$(cd "$(dirname "$0")/.." && pwd)
MOC="$HERE/bin/moc"; LINK="$HERE/tools/molink.sh"
TMP=/tmp/molftest
rm -rf $TMP && mkdir -p $TMP/lib
cp "$HERE"/lib/*.mo $TMP/lib/
cp "$HERE"/examples/lfbench.mo $TMP/
cd $TMP
PASS=0; FAIL=0
ck() { if [ "$1" = "$2" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "  ✗ $3 (得到 '$1' 想要 '$2')"; fi; }

if ! grep -q 'import "lf.mo"' lfbench.mo; then
  echo "  ✗ lfbench.mo 不再 import lf.mo：本测试会空转"; echo "通过 0 / 失败 1"; exit 1
fi
if ! $MOC lfbench.mo -c lfbench.o 2>err.txt; then
  echo "  ✗ 编译失败"; head -5 err.txt; echo "通过 0 / 失败 1"; exit 1
fi
if ! bash $LINK lfbench.o -o lfbench >/dev/null 2>&1; then
  echo "  ✗ 链接失败（libatomic 没找到？）"; echo "通过 0 / 失败 1"; exit 1
fi

timeout -s KILL -k 5 120 ./lfbench > out.txt 2>&1; RC=$?
ck "$RC" "0" "程序正常退出（挂住/崩溃都会体现为退出码）"

g() { grep -o "$1=[0-9]*" out.txt | head -1 | sed 's/.*=//'; }
ck "$(grep -o 'seq ok=1' out.txt | head -1)"      "seq ok=1"      "栈 LIFO 顺序"
ck "$(grep -o 'fifo ok=1' out.txt | head -1)"     "fifo ok=1"     "队列 FIFO 顺序"
ck "$(grep -o 'cons ok=1' out.txt | head -1)"     "cons ok=1"     "守恒：不丢不重"
ck "$(g 'npop')"    "4000" "守恒：弹出总数"
ck "$(g 'missing')" "0"    "守恒：无丢失"
ck "$(g 'dup')"     "0"    "守恒：无重复"
ck "$(g 'oob')"     "0"    "守恒：值域无越界"

# ABA：两次 t_aba 的 left 必须不同（3 vs 2）
A0=$(grep -o 'aba notag=0 commit=0 left=[0-9]*' out.txt | sed 's/.*left=//')
A1=$(grep -o 'aba notag=1 commit=1 left=[0-9]*' out.txt | sed 's/.*left=//')
ck "$A0" "3" "ABA：有 tag 时 commit 失败，元素不丢"
ck "$A1" "2" "ABA：无 tag 时 commit 成功，丢一个元素"

# UAF
U0=$(grep -o 'uaf protect=0 val=[0-9]*' out.txt | sed 's/.*val=//')
U1=$(grep -o 'uaf protect=1 val=[0-9]*' out.txt | sed 's/.*val=//')
ck "$U0" "999" "UAF：不保护时槽位被复用，读到 999"
ck "$U1" "3"   "UAF：危险指针保护时读到的仍是 3"

# 🔴 CAS 返回值通道：必然失败的 CAS 循环 200 次，返回值之和必须为 0。
#   详见 docs/lf.md —— M1 只在 EAX 高 24 位有垃圾时才发作，故用循环放大。
R=$(grep -o 'casfail rsum=[0-9]*' out.txt | head -1 | sed 's/.*=//')
ck "$R" "0" "CAS 失败必须返回 0（返回值通道不得被垃圾高位污染）"
ck "$(grep -o 'casfail rsum=0 c=100000' out.txt | head -1)" "casfail rsum=0 c=100000" "CAS 失败不得改写目标"
# 双通道交叉校验：两条通道必须始终一致
D=$(grep -o 'dual=[0-9]*' out.txt | tail -1 | sed 's/.*=//')
ck "$D" "0" "CAS 双通道（返回值 vs expected 改写）必须一致"

# 吞吐：三项都必须 > 0（判非负，不判快慢 —— 快慢依赖机器负载与核数）
B1=$(g 'lf_ms'); B2=$(g 'mt_ms'); B3=$(g 'q_ms')
if [ -n "$B1" ] && [ "$B1" -gt 0 ] 2>/dev/null; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "  ✗ 无锁栈吞吐未测到 (lf_ms='$B1')"; fi
if [ -n "$B2" ] && [ "$B2" -gt 0 ] 2>/dev/null; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "  ✗ 互斥锁栈吞吐未测到 (mt_ms='$B2')"; fi
if [ -n "$B3" ] && [ "$B3" -gt 0 ] 2>/dev/null; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "  ✗ 无锁队列吞吐未测到 (q_ms='$B3')"; fi
echo "  观测：lf_ms=$B1 mt_ms=$B2 q_ms=$B3"

echo "通过 $PASS / 失败 $FAIL"
[ $FAIL -eq 0 ]
