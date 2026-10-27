#!/bin/bash
# tbtest —— 泛型 trait bound 端到端验证
#
# 核心判据不是"正例能跑"，而是**同一份 Sneaky 在有无 bound 下结果相反**：
#   Sneaky 补齐了 Shape 要求的全部同名方法（area / perim），但从未 `impl Shape`。
#     无 bound  → 结构化匹配放行，编译通过并运行
#     有 bound  → 拒绝：Sneaky does not implement Shape
# 只看正例的话，这个特性等于没验 —— 正例在无 bound 时也全过。
#
# 每条负例都要求：退出码非 0 **且** 消息含关键串。
# 只看退出码会漏掉"因为别的语法错误而失败"的情形。
HERE=$(cd "$(dirname "$0")/.." && pwd)
MOC="$HERE/bin/moc"
TMP=/tmp/motb
rm -rf $TMP && mkdir -p $TMP/lib
cp "$HERE"/lib/*.mo $TMP/lib/
cd $TMP
PASS=0; FAIL=0
ck() { if [ "$1" = "$2" ]; then PASS=$((PASS+1)); echo "  ✓ $3"; else FAIL=$((FAIL+1)); echo "  ✗ $3 (得到 '$1' 想要 '$2')"; fi; }

echo "== A. 正例：带 bound 的泛型正常工作 =="
cp "$HERE/tests/141_traitbound.mo" t.mo
OUT=$("$MOC" t.mo a.elf 2>&1); RC=$?
ck "$RC" "0" "正例编译通过"
if [ "$RC" = "0" ]; then
    R=$(./a.elf 2>&1); ck "$R" "ran 6, failed 0" "6 项断言全过"
else
    echo "$OUT" | head -5
fi

echo "== B. 对照：同一个 Sneaky，无 bound 时**放行** =="
cat > nb.mo <<'MO'
import "io.mo";
interface Shape { fn area(self: ptr) -> i64; fn perim(self: ptr) -> i64; }
class Sneaky { z: i64; }
fn Sneaky_area(self: Sneaky) -> i64 { return self.z; }
fn Sneaky_perim(self: Sneaky) -> i64 { return self.z * 4; }
generic fn pg<T>(a: T) -> i64 { return a.perim(); }
instantiate pg(Sneaky) as pg_sneaky;
fn main() -> i64 { let s: Sneaky; s.z = 3; print_i64(pg_sneaky(s)); return 0; }
MO
OUT=$("$MOC" nb.mo nb.elf 2>&1); RC=$?
ck "$RC" "0" "无 bound：结构化匹配放行（编译通过）"
if [ "$RC" = "0" ]; then
    R=$(./nb.elf 2>&1); ck "$R" "12" "无 bound：运行输出 12"
else
    echo "$OUT" | head -5
fi
# 守卫：对照文件里必须**真的没有** impl，否则这条对照毫无意义
if grep -q "impl" nb.mo; then ck "1" "0" "守卫：对照文件不应含 impl"; fi

echo "== C. 负例：有 bound 时拒绝（名义化）=="
cat > neg.mo <<'MO'
import "io.mo";
interface Shape { fn area(self: ptr) -> i64; fn perim(self: ptr) -> i64; }
class Sneaky { z: i64; }
fn Sneaky_area(self: Sneaky) -> i64 { return self.z; }
fn Sneaky_perim(self: Sneaky) -> i64 { return self.z * 4; }
generic fn pg<T: Shape>(a: T) -> i64 { return a.perim(); }
instantiate pg(Sneaky) as pg_sneaky;
fn main() -> i64 { let s: Sneaky; s.z = 3; print_i64(pg_sneaky(s)); return 0; }
MO
OUT=$("$MOC" neg.mo neg.elf 2>&1); RC=$?
if [ "$RC" != "0" ]; then ck "1" "1" "有 bound：编译被拒绝"; else ck "0" "1" "有 bound：编译被拒绝"; fi
if echo "$OUT" | grep -q "does not implement"; then ck "1" "1" "消息含 'does not implement'"; else ck "0" "1" "消息含 'does not implement'（实际: ${OUT:0:80}）"; fi
if echo "$OUT" | grep -q "Sneaky"; then ck "1" "1" "消息点名 Sneaky"; else ck "0" "1" "消息点名 Sneaky（实际: ${OUT:0:80}）"; fi

echo "== D. 负例：多 bound 中只缺一个 =="
cat > neg2.mo <<'MO'
import "io.mo";
interface Shape { fn area(self: ptr) -> i64; }
interface Tag { fn tag(self: ptr) -> i64; }
class Rect { w: i64; h: i64; }
fn Rect_area(self: Rect) -> i64 { return self.w * self.h; }
# 🔴 Rect **有** tag 方法，只是没 `impl Tag` —— 这样结构化匹配会通过，
#    bound 检查才有机会成为唯一的拒绝者。缺的是方法时，先报的是
#    "no such method"（更具体，且发生在展开时），bound 根本轮不到。
fn Rect_tag(self: Rect) -> i64 { return 5; }
impl Shape for Rect { area; }
generic fn tg<T: Shape + Tag>(a: T) -> i64 { return a.tag(); }
instantiate tg(Rect) as tg_rect;
fn main() -> i64 { return 0; }
MO
OUT=$("$MOC" neg2.mo neg2.elf 2>&1); RC=$?
if [ "$RC" != "0" ] && echo "$OUT" | grep -q "does not implement Tag"; then
    ck "1" "1" "只 impl 了 Shape → 报缺 Tag"
else
    ck "0" "1" "只 impl 了 Shape → 报缺 Tag（实际: ${OUT:0:80}）"
fi

echo "== E. 负例：bound 里写了不存在的接口 =="
cat > neg3.mo <<'MO'
interface Shape { fn area(self: ptr) -> i64; }
class Rect { w: i64; h: i64; }
generic fn ag<T: Nope>(a: T) -> i64 { return 0; }
instantiate ag(Rect) as ag_rect;
fn main() -> i64 { return 0; }
MO
OUT=$("$MOC" neg3.mo neg3.elf 2>&1); RC=$?
if [ "$RC" != "0" ] && echo "$OUT" | grep -q "unknown interface in bound"; then
    ck "1" "1" "未知接口 → 报 unknown interface in bound"
else
    ck "0" "1" "未知接口 → 报 unknown interface in bound（实际: ${OUT:0:80}）"
fi

echo "== F. 回归：无 bound 泛型不受影响 =="
cat > reg.mo <<'MO'
import "io.mo";
generic fn maxg<T>(a: T, b: T) -> T { if a > b { return a; } return b; }
instantiate maxg(i64) as maxi;
fn main() -> i64 { print_i64(maxi(3, 9)); return 0; }
MO
OUT=$("$MOC" reg.mo reg.elf 2>&1); RC=$?
ck "$RC" "0" "无 bound 泛型仍可编译"
if [ "$RC" = "0" ]; then
    R=$(./reg.elf 2>&1); ck "$R" "9" "maxi(3,9) = 9"
else
    echo "$OUT" | head -5
fi

echo ""
echo "== 结果：PASS=$PASS FAIL=$FAIL =="
[ "$FAIL" = "0" ] || exit 1
exit 0
