#!/bin/bash
# armfsmut —— 证明 armfstest.sh **真的能抓到东西**（否则它是空转的）
#
# 三个变异各自对应一个真缺陷：
#   M1 不插入 AT_FDCWD(-100)  ← *at 参数重排失效
#   M2 open 不换号（2→56）     ← syscall 号翻译失效（docs/sysno.md 的主缺陷）
#   M3 去掉 _start 的栈对齐     ← 用到局部数组的程序一启动就 SIGSEGV
#
# M1/M2 只在 ARM64 端变红（x86-64 本来不需要适配），
# M3 只在 x86-64 端变红（那是 cfs-x86_64 专属的 _start 修正）——
# **只跑一端的话，三个变异里有两个会漏。**
set +e
cd "$(dirname "$0")/.."
ROOT=$PWD
SRC=tools/mo2x.mo
BAK=build/mo2x.mo.armfsmut.bak
mkdir -p build

# 锚点写在 python 里，不经过 shell 引号：v1.141 踩过 sed 正则锚点
# 「手工能匹配、脚本里恒判未生效」的坑。
xform(){
  python3 - "$SRC" "$1" <<'PY'
import sys
p, mode = sys.argv[1], sys.argv[2]
s = open(p).read()
PAIRS = [
 # (干净, 变异)
 ('if FS_ATINS == 1 { outs(",(long)-100"); }',
  'if FS_ATINS == 0 { outs(",(long)-100"); }'),
 ('if n == 2   { FS_ATINS = 1; return 56;  }',
  'if n == 2   { FS_ATINS = 1; return 2;   }'),
 ('asm volatile(\\"subq $8, %rsp\\")',
  'asm volatile(\\"nop\\")'),
]
if mode == 'h':                      # heal：变异 -> 干净
    for good, bad in PAIRS:
        s = s.replace(bad, good)
    open(p, 'w').write(s)
    sys.exit(0)
good, bad = PAIRS[int(mode) - 1]
if good not in s:
    sys.stderr.write("锚点不在源码里: %r\n" % good[:50]); sys.exit(1)
open(p, 'w').write(s.replace(good, bad, 1))
# 回读确认：v1.143 踩过「沙盒写入可见性延迟」—— 写完立刻被 make 读到
# 旧内容，于是变异根本没进产物，测试全绿却打印"未被捕获"。
# 不回读就等于拿一个假结论当证据。
if bad not in open(p).read():
    sys.stderr.write("变异写入后回读不到（未落盘）\n"); sys.exit(1)
PY
}

# ---- 自愈到干净态再开工 ----
# 备份不能靠 "cp 当前源码"：上一轮若被强杀，当前源码可能就是污染版，
# 那样备份、源码一起坏（v1.151 踩过）。所以先 heal，再备份。
xform h || { echo "armfsmut: 自愈失败"; exit 2; }
cp "$SRC" "$BAK"

rebuild(){ rm -f bin/mo2x; make mo2x >/dev/null 2>&1; }

echo "armfsmut:"
rebuild
timeout 300 bash tools/armfstest.sh >/dev/null 2>&1
if [ $? -ne 0 ]; then
  echo "  ✗ 基线未通过 —— 后续结论无意义"
  cp "$BAK" "$SRC"; rebuild; exit 1
fi
echo "  ✓ 基线通过"

bad=0
for m in 1 2 3; do
  case $m in
    1) NAME="M1 不插入 AT_FDCWD(-100)";;
    2) NAME="M2 open 不换号(2→56)";;
    3) NAME="M3 去掉 _start 栈对齐";;
  esac
  if ! xform $m; then
    echo "  ✗ $NAME 未能应用（锚点失效）"; bad=1; continue
  fi
  rebuild
  OUT=$(timeout 300 bash tools/armfstest.sh 2>&1); RC=$?
  N=$(echo "$OUT" | grep -c "✗")
  cp "$BAK" "$SRC"; rebuild        # 每次都还原，绝不带变异进下一轮
  if [ $RC -ne 0 ]; then
    echo "  ✓ $NAME 变异被捕获（$N 项变红，退出码 $RC）"
  else
    echo "  ✗ $NAME 变异未被捕获 —— armfstest 在此处是空转的"
    echo "$OUT" | sed 's/^/      | /'   # 打出全部判据，便于分辨是"真通过"还是"判据失效"
    bad=1
  fi
done

xform h; rebuild
if [ $bad -eq 0 ]; then echo "armfsmut: OK（3 个变异全部被捕获）"
else echo "armfsmut: 存在未被捕获的变异"; exit 1; fi
