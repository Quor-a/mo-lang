#!/bin/bash
# nscheckmut —— 证明 nschecktest 的断言不是空转
#
# 做法：把 nscheck.py 改回缺陷状态，看自检会不会红。
# 只看「7 项全过」证明不了什么 —— 必须逐个确认改的是不是那条因果链。
#
# 本项目已多次栽在变异脚本自己身上：备份被删、还原没落盘、源码停在变异态
# 而脚本照样打印全绿。这里的对策是
#   * 备份放 build/ 下（/tmp 会被清），且不删
#   * 收尾逐字节 diff 复检 —— 不看"改过了"，看"现在确实一样"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
cd "$HERE" || exit 1
PY=tools/nscheck.py
BAK=build/nscheck.py.bak
pass=0; fail=0   # 未初始化时收尾的 [ "$fail" = 0 ] 会把空串判为失败
mkdir -p build
cp "$PY" "$BAK"

# 锚点：干净 -> 变异
A1='if len(set(b for b, _ in cands)) < 2:'
B1='if len(set(b for b, _ in cands)) < 3:'
A2='if nm in own:'
B2='if False and nm in own:'
A3='    cand = os.path.normpath(os.path.join(cwd, path))'
B3='    cand = path'

inject() { # inject <变异后内容> <锚点原文>
  python3 - "$PY" "$1" "$2" <<'EOF'
import sys
p, new, old = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(p, encoding='utf-8').read()
assert s.count(old) == 1, "锚点出现 %d 次（应为 1）：%s" % (s.count(old), old)
open(p, 'w', encoding='utf-8').write(s.replace(old, new))
EOF
}

mut() { # mut <名字> <变异内容> <锚点原文>
  local name=$1 new=$2 old=$3
  if ! inject "$new" "$old"; then
    echo "FAIL $name 注入失败（锚点不唯一）"; fail=$((fail+1)); return
  fi
  bash tools/nschecktest.sh >/tmp/nsmut.out 2>&1; rc=$?
  cp "$BAK" "$PY"
  if ! diff -q "$BAK" "$PY" >/dev/null; then
    echo "FAIL $name 还原未落盘"; fail=$((fail+1)); return
  fi
  if [ "$rc" -ne 0 ]; then
    echo "PASS $name 变异被捕获 -> $(grep -m1 'failed' /tmp/nsmut.out)"
    pass=$((pass+1))
  else
    echo "FAIL $name 变异未被捕获（nschecktest 仍绿）"; fail=$((fail+1))
  fi
}

echo "=== 基线（必须 7/7）==="
bash tools/nschecktest.sh >/tmp/nsbase.out 2>&1 && echo "PASS 基线 $(grep -m1 'ran' /tmp/nsbase.out)" \
  || { echo "FAIL 基线不过"; cat /tmp/nsbase.out; }

echo
echo "=== 变异 ==="
mut "M1 歧义阈值放宽到 3（永不报）" "$B1" "$A1"
mut "M2 不排除本文件自己的定义"      "$B2" "$A2"
mut "M3 import 退回进程 cwd 解析"    "$B3" "$A3"

echo
echo "=== 收尾复检：源码必须与开工时逐字节一致 ==="
if diff -q "$BAK" "$PY" >/dev/null; then
  echo "PASS 源码已还原"; pass=$((pass+1))
else
  echo "FAIL 源码仍处于变异态"; diff "$BAK" "$PY" | head; fail=$((fail+1))
fi

echo
echo "nscheckmut: pass=$pass fail=$fail"
[ "$fail" = 0 ]
