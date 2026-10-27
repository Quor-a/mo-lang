#!/bin/bash
# cspmut —— CSP 的变异验证：证明 csptest 的断言真的在起作用
#
# 只看"8 项全过"证明不了什么 —— channel 顺序错、唤醒失效、交接标记缺失
# 都可能碰巧仍然通过。这里逐个把它们改坏，确认测试会变红。
#
# 每个变异：改源码 → 重编 csp → 跑 csptest → 还原 → 核对源码确实干净。
HERE=$(cd "$(dirname "$0")/.." && pwd)
LIB="$HERE/lib/csp.mo"
BAK=$(mktemp /tmp/cspbak.XXXXXX)
cp "$LIB" "$BAK"
restore() { cp "$BAK" "$LIB"; }
trap restore EXIT

mutate() { # $1=名字 $2=旧 $3=新
  python3 - "$LIB" "$2" "$3" <<'PY'
import sys
p, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(p).read()
assert s.count(old) == 1, (old, s.count(old))
open(p, 'w').write(s.replace(old, new))
PY
}

run() {
  local name="$1"
  shift
  mutate "$name" "$1" "$2"
  echo "== 变异 $name =="
  bash "$HERE/tools/csptest.sh" 2>&1 | grep -E "^通过|✗" | sed 's/^/   /'
  restore
  # 用整文件比对确认还原 —— 按"新字符串是否还在"判断会误报
  # （新字符串可能是源码里别处也有的常见片段，如 `return 0;`）
  if ! cmp -s "$BAK" "$LIB"; then
    echo "   ✗ 还原失败：源码与备份不一致"; return 1
  fi
  return 0
}

# M1：缓冲 channel 改成 LIFO（从 tail 取）→ FIFO 断言必须失败
run "M1 缓冲改成 LIFO（破坏顺序）" \
    'let v: i64 = CH_BUF[b + CH_H[c]];' \
    'let v: i64 = CH_BUF[b + CH_T[c] - 1];'

# M2：去掉发送后的唤醒 → 阻塞的接收者永远醒不过来 → 死锁检测触发
run "M2 去掉唤醒（阻塞不可恢复）" \
    '                csp_wakech(c);
                return 0;' \
    '                return 0;'

# M3：无缓冲交接不置标记 → 接收方拿不到值，挂在 rendezvous 上
run "M3 无缓冲交接去掉标记" \
    'CSP_WR[r] = 1;' \
    'CSP_WR[r] = 0;'

restore
echo "== 基线（还原后） =="
bash "$HERE/tools/csptest.sh" 2>&1 | grep -E "^通过"
trap - EXIT
rm -f "$BAK"
