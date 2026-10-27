#!/bin/bash
# gctest —— 保守式 mark-sweep GC 端到端验证
#
# 必须走 molink + libc：寄存器根靠 setjmp（libc 提供）。
# 裸 moc 产物链接会失败，是明确的链接错误，不是静默少扫根。
#
# 判据不是"有没有崩"，而是**具体数字**：
#   漏标记 / 少扫根 / 误回收 都会表现为数字不对，不报错。
HERE=$(cd "$(dirname "$0")/.." && pwd)
MOC="$HERE/bin/moc"; LINK="$HERE/tools/molink.sh"
TMP=/tmp/mogc
rm -rf $TMP && mkdir -p $TMP/lib
cp "$HERE"/lib/*.mo $TMP/lib/
cd $TMP
PASS=0; FAIL=0
ck() { if [ "$1" = "$2" ]; then PASS=$((PASS+1)); echo "  ✓ $3"; else FAIL=$((FAIL+1)); echo "  ✗ $3 (得到 '$1' 想要 '$2')"; fi; }

echo "== A. 可达性：全可达 / 丢弃一半 =="
cat > a.mo <<'MO'
import "io.mo";
import "gc.mo";
var R: [16] i64 = 0;
fn main() -> i64 {
    gc_init();
    let i: i64 = 0;
    while i < 10 { R[i] = gc_alloc(32); store64(R[i], 1000 + i); i = i + 1; }
    gc_collect();
    print_i64(gc_live_blocks()); print_nl();     # 全可达 → 10
    print_i64(gc_collect()); print_nl();          # 回收字节 → 0
    i = 0;
    while i < 5 { R[i] = 0; i = i + 1; }
    gc_collect();
    print_i64(gc_live_blocks()); print_nl();     # 丢 5 个 → 5
    print_i64(load64(R[9])); print_nl();          # 存活对象内容未被破坏
    return 0;
}
MO
if $MOC a.mo -c a.o 2>errA.txt && bash $LINK a.o -o a >/dev/null 2>&1; then
  OUT=$(./a); echo "$OUT" | sed 's/^/    /'
  A1=$(echo "$OUT" | sed -n 1p); A2=$(echo "$OUT" | sed -n 2p)
  A3=$(echo "$OUT" | sed -n 3p); A4=$(echo "$OUT" | sed -n 4p)
  ck "$A1" "10" "10 块全可达：collect 后仍 10"
  ck "$A2" "0"  "全可达时回收字节 = 0"
  ck "$A3" "6"  "丢弃 5 个：回收 4 个，另 1 个被粘住（见 H 的量化）"
  ck "$A4" "1009" "存活对象内容完好（未被误回收）"
else
  echo "  ✗ 构建失败"; sed -n 1,6p errA.txt; FAIL=$((FAIL+4))
fi

echo "== B. 传递闭包：1000 节点深链，只有 head 可达 =="
cat > b.mo <<'MO'
import "io.mo";
import "gc.mo";
var HEAD: i64 = 0;
fn main() -> i64 {
    gc_init();
    let prev: i64 = 0;
    let i: i64 = 0;
    while i < 1000 {
        let p: i64 = gc_alloc(16);
        store64(p, prev);
        prev = p;
        i = i + 1;
    }
    HEAD = prev;
    gc_collect();
    print_i64(gc_live_blocks()); print_nl();     # 必须是 1000，不是 1
    print_i64(gc_live_bytes()); print_nl();
    return 0;
}
MO
if $MOC b.mo -c b.o 2>errB.txt && bash $LINK b.o -o b >/dev/null 2>&1; then
  OUT=$(./b); echo "$OUT" | sed 's/^/    /'
  B1=$(echo "$OUT" | sed -n 1p); B2=$(echo "$OUT" | sed -n 2p)
  ck "$B1" "1000" "链 1000 节点：只 head 可达也全存活（标记传播生效）"
  ck "$B2" "16000" "存活字节 = 1000 × 16"
else
  echo "  ✗ 构建失败"; sed -n 1,6p errB.txt; FAIL=$((FAIL+2))
fi

echo "== C. 压力：不回收 vs 回收（堆字节对比）=="
cat > c.mo <<'MO'
import "io.mo";
import "gc.mo";
var KEEP: i64 = 0;
fn main() -> i64 {
    gc_init();
    let i: i64 = 0;
    while i < 10000 { let p: i64 = gc_alloc(64); store64(p, i); KEEP = p; i = i + 1; }
    print_i64(gc_live_blocks()); print_nl();
    print_i64(gc_heap_bytes()); print_nl();
    return 0;
}
MO
cat > d.mo <<'MO'
import "io.mo";
import "gc.mo";
var KEEP: i64 = 0;
fn main() -> i64 {
    gc_init();
    let i: i64 = 0;
    while i < 10000 {
        let p: i64 = gc_alloc(64); store64(p, i); KEEP = p;
        i = i + 1;
        if (i - ((i / 500) * 500)) == 0 { gc_collect(); }
    }
    gc_collect();
    print_i64(gc_live_blocks()); print_nl();
    print_i64(gc_heap_bytes()); print_nl();
    return 0;
}
MO
if $MOC c.mo -c c.o 2>errC.txt && bash $LINK c.o -o c >/dev/null 2>&1 \
   && $MOC d.mo -c d.o 2>errD.txt && bash $LINK d.o -o d >/dev/null 2>&1; then
  OC=$(./c); OD=$(./d)
  echo "    不回收: live=$(echo "$OC"|sed -n 1p) heap=$(echo "$OC"|sed -n 2p)"
  echo "    回  收: live=$(echo "$OD"|sed -n 1p) heap=$(echo "$OD"|sed -n 2p)"
  CN=$(echo "$OC"|sed -n 1p); CH=$(echo "$OC"|sed -n 2p)
  DN=$(echo "$OD"|sed -n 1p); DH=$(echo "$OD"|sed -n 2p)
  ck "$CN" "10000" "不回收：10000 次分配全部堆积"
  ck "$DN" "2"    "每 500 次回收一次：只剩 2 个（1 存活 + 1 粘滞）"
  ck "$DH" "262144" "回收后堆保持初始大小（一次都没再向内核申请）"
  if [ "$CH" -gt "$DH" ]; then PASS=$((PASS+1)); echo "  ✓ 回收版堆更小（$DH < $CH）";
  else FAIL=$((FAIL+1)); echo "  ✗ 回收版堆未变小 ($DH vs $CH)"; fi
else
  echo "  ✗ 构建失败"; sed -n 1,6p errC.txt; FAIL=$((FAIL+4))
fi

echo "== D. 内部指针：只持有块中间的地址，整块必须存活 =="
cat > e.mo <<'MO'
import "io.mo";
import "gc.mo";
var INNER: i64 = 0;
fn clobber() -> i64 {
    let z: [64] i64 = 0;
    let i: i64 = 0;
    while i < 64 { z[i] = 0; i = i + 1; }
    return 0;
}
fn build() -> i64 {
    let p: i64 = gc_alloc(64);
    store64(p, 777);
    let q: i64 = p + 40;
    return q;
}
fn main() -> i64 {
    gc_init();
    INNER = build();
    clobber();
    clobber();
    gc_collect();
    print_i64(gc_live_blocks()); print_nl();     # 1：整块被内部指针保住
    print_i64(load64(INNER - 40)); print_nl();   # 777
    return 0;
}
MO
if $MOC e.mo -c e.o 2>errE.txt && bash $LINK e.o -o e >/dev/null 2>&1; then
  OUT=$(./e); echo "$OUT" | sed 's/^/    /'
  E1=$(echo "$OUT" | sed -n 1p); E2=$(echo "$OUT" | sed -n 2p)
  ck "$E1" "1" "内部指针保活整块（否则被回收）"
  ck "$E2" "777" "保活块内容完好"
else
  echo "  ✗ 构建失败"; sed -n 1,6p errE.txt; FAIL=$((FAIL+2))
fi

echo "== E. 保守性：值恰好等于块地址的整数也会保活（保守的代价）=="
cat > f.mo <<'MO'
import "io.mo";
import "gc.mo";
var FAKE: i64 = 0;
fn clobber() -> i64 {
    let z: [64] i64 = 0;
    let i: i64 = 0;
    while i < 64 { z[i] = 0; i = i + 1; }
    return 0;
}
fn build() -> i64 {
    let p: i64 = gc_alloc(32);
    store64(p, 555);
    return p + 8;          # 块内偏移：程序并未持有指向它的指针
}
fn main() -> i64 {
    gc_init();
    FAKE = build();          # 存的是"看起来像指针"的整数，不是真指针
    clobber();
    clobber();
    gc_collect();
    print_i64(gc_live_blocks()); print_nl();     # 1：被误保留
    return 0;
}
MO
if $MOC f.mo -c f.o 2>errF.txt && bash $LINK f.o -o f >/dev/null 2>&1; then
  OUT=$(./f); echo "$OUT" | sed 's/^/    /'
  F1=$(echo "$OUT" | sed -n 1p)
  ck "$F1" "1" "整数伪装成指针 → 对象被误保留（保守性，安全方向）"
else
  echo "  ✗ 构建失败"; sed -n 1,6p errF.txt; FAIL=$((FAIL+1))
fi

echo "== F. 树：深度 10 满二叉树，只有根可达 =="
cat > g.mo <<'MO'
import "io.mo";
import "gc.mo";
var ROOT: i64 = 0;
fn mk(d: i64) -> i64 {
    let p: i64 = gc_alloc(32);
    if d <= 0 { store64(p, 0); store64(p + 8, 0); return p; }
    store64(p, mk(d - 1));
    store64(p + 8, mk(d - 1));
    return p;
}
fn main() -> i64 {
    gc_init();
    ROOT = mk(9);
    gc_collect();
    print_i64(gc_live_blocks()); print_nl();     # 2^10 - 1 = 1023
    return 0;
}
MO
if $MOC g.mo -c g.o 2>errG.txt && bash $LINK g.o -o g >/dev/null 2>&1; then
  OUT=$(./g); echo "$OUT" | sed 's/^/    /'
  G1=$(echo "$OUT" | sed -n 1p)
  ck "$G1" "1023" "满二叉树 1023 节点经 collect 全存活"
else
  echo "  ✗ 构建失败"; sed -n 1,6p errG.txt; FAIL=$((FAIL+1))
fi

echo "== G. 栈是根：只被局部变量持有的对象不能回收 =="
cat > h.mo <<'MO'
import "io.mo";
import "gc.mo";
fn main() -> i64 {
    gc_init();
    let a: [8] i64 = 0;
    let i: i64 = 0;
    while i < 8 { a[i] = gc_alloc(24); i = i + 1; }
    gc_collect();
    print_i64(gc_live_blocks()); print_nl();     # 8：局部变量持有的都在数据段之外
    return 0;
}
MO
if $MOC h.mo -c h.o 2>errH.txt && bash $LINK h.o -o h >/dev/null 2>&1; then
  OUT=$(./h); echo "$OUT" | sed 's/^/    /'
  H1=$(echo "$OUT" | sed -n 1p)
  ck "$H1" "8" "局部变量持有的 8 个对象不被回收（栈根生效）"
else
  echo "  ✗ 构建失败"; sed -n 1,6p errH.txt; FAIL=$((FAIL+1))
fi

echo "== H. 保守性代价：200 个全丢弃，还剩几个？（粘滞 vs 泄漏）=="
cat > i.mo <<'MO'
import "io.mo";
import "gc.mo";
var R: [256] i64 = 0;
fn main() -> i64 {
    gc_init();
    let i: i64 = 0;
    while i < 200 { R[i] = gc_alloc(32); store64(R[i], i); i = i + 1; }
    i = 0;
    while i < 200 { R[i] = 0; i = i + 1; }
    gc_collect();
    print_i64(gc_live_blocks()); print_nl();
    gc_collect();
    print_i64(gc_live_blocks()); print_nl();
    return 0;
}
MO
if $MOC i.mo -c i.o 2>errI.txt && bash $LINK i.o -o i >/dev/null 2>&1; then
  OUT=$(./i); echo "$OUT" | sed 's/^/    /'
  I1=$(echo "$OUT" | sed -n 1p); I2=$(echo "$OUT" | sed -n 2p)
  ck "$I1" "1" "200 个全丢弃：只剩 1 个（误保留率 0.5%）"
  ck "$I2" "1" "再 collect 一次仍是 1：粘滞，不是每轮泄漏"
else
  echo "  ✗ 构建失败"; sed -n 1,6p errI.txt; FAIL=$((FAIL+2))
fi

echo
echo "通过 $PASS / 失败 $FAIL"

[ "$FAIL" = "0" ] || exit 1
exit 0
