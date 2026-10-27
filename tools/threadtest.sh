#!/bin/bash
# threadtest —— 线程与同步的端到端验证
#
# 关键是"结果必须精确"：无锁或锁失效时计数会**少于**期望值，
#  而不是崩溃 —— 所以必须比对具体数字，不能只看退出码。
HERE=$(cd "$(dirname "$0")/.." && pwd)
MOC="$HERE/bin/moc"; LINK="$HERE/tools/molink.sh"
TMP=/tmp/mothread
rm -rf $TMP && mkdir -p $TMP/lib
cp "$HERE"/lib/*.mo $TMP/lib/
cd $TMP
PASS=0; FAIL=0
ck() { if [ "$1" = "$2" ]; then PASS=$((PASS+1)); echo "  ✓ $3"; else FAIL=$((FAIL+1)); echo "  ✗ $3 (得到 '$1' 想要 '$2')"; fi; }

cat > t.mo <<'MO'
import "io.mo";
import "thread.mo";

var CNT: i64 = 0;
var MTX: [8] i64 = 0;
var T1: i64 = 0;
var T2: i64 = 0;
var T3: i64 = 0;

fn worker(arg: ptr) -> i64 {
    let i: i64 = 0;
    while i < 20000 {
        mutex_lock(&MTX);
        CNT = CNT + 1;
        mutex_unlock(&MTX);
        i = i + 1;
    }
    return 0;
}

fn main() -> i64 {
    if mutex_init(&MTX) != 0 { print("mutex_init failed\n"); return 1; }
    if thread_create(&T1, &worker, 0) != 0 { return 1; }
    if thread_create(&T2, &worker, 0) != 0 { return 1; }
    if thread_create(&T3, &worker, 0) != 0 { return 1; }
    thread_join(T1); thread_join(T2); thread_join(T3);
    print("CNT = "); print_i64(CNT); print("\n");
    if CNT != 60000 { return 1; }
    return 0;
}
MO
$MOC t.mo -c t.o >/dev/null 2>&1
bash "$LINK" t.o -o t >/dev/null 2>&1
OUT=$(./t 2>&1)
ck "$(echo "$OUT" | head -1)" "CNT = 60000" "3 线程 × 20000 次加锁自增，结果精确"
RC=0; ./t >/dev/null 2>&1 || RC=$?
ck "$RC" "0" "退出码 0"

# 无锁对照：证明上面的数字确实说明锁有效
cat > n.mo <<'MO'
import "io.mo";
import "thread.mo";
var CNT2: i64 = 0;
var TA: i64 = 0;
var TB: i64 = 0;
fn bump(arg: ptr) -> i64 {
    let i: i64 = 0;
    while i < 2000000 { CNT2 = CNT2 + 1; i = i + 1; }
    return 0;
}
fn main() -> i64 {
    thread_create(&TA, &bump, 0);
    thread_create(&TB, &bump, 0);
    thread_join(TA); thread_join(TB);
    print("nolock = "); print_i64(CNT2); print("\n");
    return 0;
}
MO
$MOC n.mo -c n.o >/dev/null 2>&1
bash "$LINK" n.o -o n >/dev/null 2>&1
V=$(./n 2>&1 | head -1 | sed 's/[^0-9]//g')
if [ "$V" != "4000000" ]; then PASS=$((PASS+1)); echo "  ✓ 无锁对照确实丢更新 ($V != 4000000)，说明上面的锁是真的在起作用"; else FAIL=$((FAIL+1)); echo "  ✗ 无锁也没丢更新，无法证明锁有效"; fi

# 全局变量地址必须 16 对齐（不对齐会让 glibc 的 futex abort）
cat > a.mo <<'MO'
import "io.mo";
var A: i64 = 1;
var B: i64 = 2;
var C: [8] i64 = 0;
fn main() -> i64 {
    print_i64(&A); print(" "); print_i64(&B); print(" "); print_i64(&C); print("\n");
    return 0;
}
MO
$MOC a.mo -c a.o >/dev/null 2>&1
bash "$LINK" a.o -o a >/dev/null 2>&1
ADDRS=$(./a)
OK=1
for x in $ADDRS; do if [ $((x % 16)) -ne 0 ]; then OK=0; fi; done
ck "$OK" "1" "全局变量地址 16 对齐 ($ADDRS)"

echo ""
echo "通过 $PASS / 失败 $FAIL"
[ "$FAIL" = "0" ]
