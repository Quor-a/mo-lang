#!/bin/bash
# utf8 —— 变异验证
#
# 「64 项全过」证明不了断言非空转：把实现改坏，断言必须变红。
# 每个变异只改一处，跑 tests/126_utf8.mo，看失败数是否上升。
#
# M5 是刻意保留的**预期不被捕获**的变异：11111xxx 的 bad 检查与
# 0xF5..0xFF 的范围检查完全重叠，去掉它结果不变。把它写出来，
# 是为了说明"改了代码却没变红"这件事本身也要被看见，而不是被挑掉。
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
LIB="$HERE/lib/utf8.mo"
BAK=$(mktemp)
cp "$LIB" "$BAK"
restore() { cp "$BAK" "$LIB"; rm -f "$BAK"; }
trap restore EXIT

run() {
  rm -rf /tmp/mot && mkdir -p /tmp/mot
  cp "$HERE"/lib/*.mo /tmp/mot/
  cp "$HERE/tests/126_utf8.mo" /tmp/mot/test.mo
  ( cd /tmp/mot && "$HERE/bin/moc" test.mo out.elf >/dev/null 2>&1 ) || { echo "编译失败"; return 99; }
  chmod +x /tmp/mot/out.elf 2>/dev/null
  ( cd /tmp/mot && ./out.elf >/dev/null 2>&1 ); echo $?
}

echo "== 基线（未变异）=="
B=$(run)
echo "   退出码 $B  （0 = 全过）"
echo

# 三段分开存：sed 表达式里含 '|'，不能再用 '|' 当字段分隔符
NAME=(
  "M1 去掉全部范围检查（越长/代理对/超上界）"
  "M2 去掉跨块续接 U8NEED"
  "M3 去掉特殊前导跨块 U8XE0"
  "M4 去掉收尾截断检查"
  "M5 去掉 bad（11111xxx）检查"
)
SEDX=(
  's/if r != 0 { return 1; }/if 0 != 0 { return 1; }/'
  's/exp = exp | U8NEED;/exp = exp | 0;/'
  's/r = r | (U8XE0 & not5);/r = r | 0;/'
  's/if U8NEED != 0 { return 0; }/if 0 != 0 { return 0; }/'
  's/if bad != 0 { return 1; }/if 0 != 0 { return 1; }/'
)
MUST=(yes yes yes yes info)

ok=0; bad_n=0
for idx in 0 1 2 3 4; do
  name="${NAME[$idx]}"; sedx="${SEDX[$idx]}"; must="${MUST[$idx]}"
  cp "$BAK" "$LIB"
  sed -i "$sedx" "$LIB"
  if diff -q "$BAK" "$LIB" >/dev/null; then
    echo "✗ $name：变异没生效（sed 未命中），脚本无效"
    bad_n=$((bad_n+1)); continue
  fi
  R=$(run)
  if [ "$R" != "0" ]; then
    echo "✓ $name → 被捕获（退出码 $R）"
    ok=$((ok+1))
  else
    if [ "$must" = "yes" ]; then
      echo "✗ $name → 未被捕获！断言形同虚设"
      bad_n=$((bad_n+1))
    else
      echo "· $name → 未被捕获（预期：该检查是冗余的）"
    fi
  fi
done

echo
echo "必须被捕获的变异：$ok 个被捕获，$bad_n 个有问题"
[ "$bad_n" = 0 ]
