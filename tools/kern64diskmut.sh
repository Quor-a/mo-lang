#!/bin/bash
# kern64diskmut.sh —— 证明 kern64disktest.sh 的判据真的在起作用
#
# 做法：把 virtio-blk 驱动改坏四种，每种都必须让测试变红。
# 若某个变异"改了代码但测试仍全绿"，说明那条判据是空转的 ——
# 这是本项目反复出现、也反复被记下的一类失效。
#
# 四个变异各自对应的因果链：
#   M1 不认 magic      → 有盘也当没盘，挂载路径整体消失
#   M2 方向位恒为 1    → 读盘时设备不写回数据，读到的全是 0
#   M3 不等 used 环    → 请求还没完成就返回，读到上一次的残留
#   M4 超级块写错扇区  → 第二次启动挂不上，只能重新格式化
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
SRC=examples/kern64disk.mo
BAK=build/kern64disk.mo.bak
mkdir -p build
cp "$SRC" "$BAK"

restore() { cp "$BAK" "$SRC"; }
trap restore EXIT INT TERM

apply() {
    python3 - "$SRC" "$1" "$2" <<'PY'
import sys
p, a, b = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(p).read()
if a not in s:
    sys.stderr.write("锚点未命中: %r\n" % a[:40]); sys.exit(3)
open(p, "w").write(s.replace(a, b, 1))
PY
}

try_mut() {
    local name=$1 a=$2 b=$3
    restore
    if ! apply "$a" "$b"; then
        echo "!! $name 锚点未命中（变异未生效）"
        echo "$name: 未验证"
        return
    fi
    bash tools/kern64disktest.sh >/tmp/k64diskmut.log 2>&1
    # 早先写的是 grep -q "0 失败"，而 "11 通过 / 10 失败" 里也含 "0 失败"
    # —— 于是四个变异明明都被抓到，脚本仍报"未被捕获"。
    # 必须带前导空格，才不会把 10 匹配成 0。
    if grep -q " 0 失败" /tmp/k64diskmut.log; then
        echo "!! $name 未被捕获（测试仍全绿 —— 判据空转）"
    else
        echo "ok $name 被捕获: $(grep -c '✗' /tmp/k64diskmut.log) 项变红"
    fi
}

try_mut "M1 不认 magic" \
    "if mmio_rd(0) != 1953655158 { return -1; }" \
    "if mmio_rd(0) != 0 { return -1; }"

try_mut "M2 描述符方向位恒为 1" \
    "    if wr == 1 { put16(d0 + 28, 1); }
    else { put16(d0 + 28, 3); }" \
    "    put16(d0 + 28, 1);"

try_mut "M3 不等 used 环" \
    "    while n < 5000 {" \
    "    while n < 0 {"

try_mut "M4 超级块写错扇区" \
    "    if wrsec(0) != 0 { return -1; }" \
    "    if wrsec(2) != 0 { return -1; }"

restore
echo "--- 还原后基线 ---"
bash tools/kern64disktest.sh 2>&1 | tail -1
