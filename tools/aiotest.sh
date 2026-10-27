#!/bin/bash
# aiotest —— 异步 I/O（epoll reactor + CSP 协程）端到端验证
#
# 必须走 molink + libc：epoll / pthread / ucontext 都在 libc 里。
#
# 判据不是"有没有崩"，而是**每个请求都必须被服务**：
#   NCLIENT(24) × NROUND(3) = 72。漏唤醒表现为 req 停在 71 且程序永不退出
#   （客户端卡在 tcp_recv，main 卡在 thread_join）—— 不报错、不崩溃。
#   所以必须**重复跑**：单次通过说明不了什么，本例漏唤醒概率约 1/5。
HERE=$(cd "$(dirname "$0")/.." && pwd)
MOC="$HERE/bin/moc"; LINK="$HERE/tools/molink.sh"
N=${N:-15}
TMP=/tmp/moaiotest
rm -rf $TMP && mkdir -p $TMP/lib
cp "$HERE"/lib/*.mo $TMP/lib/
cp "$HERE"/examples/httpsrv.mo $TMP/
cd $TMP
PASS=0; FAIL=0
ck() { if [ "$1" = "$2" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "  ✗ $3 (得到 '$1' 想要 '$2')"; fi; }

# 🔴 守卫：示例必须真的 import "aio.mo"。
#    若哪天有人把这行删了，示例会退化成阻塞 I/O，而本测试**照样全绿** ——
#    那就成了"通过了但什么都没验到"。这条断言就是防它。
if ! grep -q 'import "aio.mo"' httpsrv.mo; then
  echo "  \u2717 httpsrv.mo 不再 import aio.mo：本测试会空转"; echo "通过 0 / 失败 1"; exit 1
fi

if ! $MOC httpsrv.mo -c httpsrv.o 2>err.txt; then
  echo "  ✗ 编译失败"; head -5 err.txt; echo "通过 0 / 失败 1"; exit 1
fi
if ! bash $LINK httpsrv.o -o httpsrv >/dev/null 2>&1; then
  echo "  ✗ 链接失败"; echo "通过 0 / 失败 1"; exit 1
fi

okrun=0; hang=0; badreq=0
i=1
while [ $i -le $N ]; do
  timeout -s KILL 20 ./httpsrv > out$i.txt 2>&1; RC=$?
  if [ $RC -ne 0 ]; then
    hang=$((hang+1))
    echo "  ✗ 第 $i 次挂住（退出码 $RC，$(grep -o 'req=[0-9]*' out$i.txt | tail -1)）"
  else
    R=$(grep -o 'req=72' out$i.txt | head -1)
    B=$(grep -o 'bad=0' out$i.txt | head -1)
    if [ -n "$R" ] && [ -n "$B" ]; then okrun=$((okrun+1)); else
      badreq=$((badreq+1))
      echo "  ✗ 第 $i 次未完成：$(grep -o 'req=[0-9]* bad=[0-9]*' out$i.txt | head -1)"
    fi
  fi
  i=$((i+1))
done

ck "$hang"    "0"  "无挂起（漏唤醒会表现为永不退出）"
ck "$badreq"  "0"  "每次都服务完 72 个请求"
ck "$okrun"   "$N" "$N 次全部通过"

echo "通过 $PASS / 失败 $FAIL"
[ $FAIL -eq 0 ]
