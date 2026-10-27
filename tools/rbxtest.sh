#!/bin/bash
# rbxtest —— callee-saved rbx 保存/恢复的端到端验证
#
# 为什么必须专门测：rbx 被栈顶缓存当中转（mov rbx,rax），不保存就违反
# SysV ABI。症状**不是报错**，而是只在"C 回调进墨函数"的边界上发作，
# 且取决于函数体里有没有用到缓存：
#
#   · glibc __start_context 从 rbx 取 uc_link      → 协程 return 就 SIGSEGV
#   · qsort 比较器 / pthread 回调                  → C 侧的 rbx 被改坏
#
# 空协程（函数体里没用到缓存）**不受影响** —— 所以只测空协程永远绿。
# 判据是"程序走完全程 + 退出码"，不是"有没有崩"。
HERE=$(cd "$(dirname "$0")/.." && pwd)
MOC="$HERE/bin/moc"; LINK="$HERE/tools/molink.sh"
TMP=/tmp/morbx
rm -rf $TMP && mkdir -p $TMP/lib
cp "$HERE"/lib/*.mo $TMP/lib/
cd $TMP
PASS=0; FAIL=0
ck() { if [ "$1" = "$2" ]; then PASS=$((PASS+1)); echo "  ✓ $3"; else FAIL=$((FAIL+1)); echo "  ✗ $3 (得到 '$1' 想要 '$2')"; fi; }

# ---- 1) 裸 ucontext：协程 return 而不是 csp_exit ----
cat > u.mo <<'MO'
import "io.mo";
extern fn getcontext(p: ptr) -> i32;
extern fn swapcontext(a: ptr, b: ptr) -> i32;
extern fn makecontext(p: ptr, f: ptr, argc: i64) -> i32;

var MAIN: [160] i64 = 0;
var CORO: [160] i64 = 0;
var STK: [8192] i64 = 0;

# 空协程：函数体里没有用到栈顶缓存，rbx 没被改 —— 修复前后都正常
fn empty_coro() -> i64 { return 0; }
# 调过 print：print 内部用到了缓存，rbx 被改坏
fn clob_coro() -> i64 { print("in coro\n"); return 0; }

fn go(f: ptr) -> i64 {
    getcontext(&CORO);
    store64(&CORO + 8, &MAIN);          # uc_link
    store64(&CORO + 16, &STK);          # ss_sp
    store64(&CORO + 24, 0);
    store64(&CORO + 32, 8192 * 8);      # ss_size
    makecontext(&CORO, f, 0);
    swapcontext(&MAIN, &CORO);
    return 0;
}

fn main() -> i64 {
    print("A\n");
    go(&empty_coro);
    print("B\n");
    go(&clob_coro);
    print("C\n");
    return 0;
}
MO

if $MOC u.mo -c u.o 2>err1.txt && bash $LINK u.o -o u >/dev/null 2>&1; then
  timeout 30 ./u > out1.txt 2>&1; RC=$?
  g() { grep -c "^$1$" out1.txt; }
  ck "$(g A)"        "1" "空协程 return 后回到主流程"
  ck "$(g B)"        "1" "空协程走完（对照组：修复前后都应通过）"
  ck "$(g 'in coro')" "1" "被改坏 rbx 的协程仍能执行"
  ck "$(g C)"        "1" "★ 该协程 return 后正确回到主流程（rbx 已恢复）"
  ck "$RC"           "0" "退出码 0（修复前这里是 139 SIGSEGV）"
else
  echo "  ✗ 编译/链接失败"; head -5 err1.txt; FAIL=$((FAIL+5))
fi

# ---- 2) csp.mo：协程不用 csp_exit，直接 return ----
# 修复前必须靠 csp_exit() 绕开 ret；现在 return 本身就是安全的。
cat > c.mo <<'MO'
import "io.mo";
import "csp.mo";
var CB: i64 = 0;
var SUM: i64 = 0;

fn prod() -> i64 {
    chan_send(CB, 7);
    chan_send(CB, 8);
    return 0;                 # 不用 csp_exit
}
fn cons() -> i64 {
    let i: i64 = 0;
    while i < 2 {
        let v: i64 = chan_recv(CB);
        SUM = SUM + v;
        i = i + 1;
    }
    return 0;                 # 不用 csp_exit
}

fn main() -> i64 {
    if csp_init(1) != 0 { print("init fail\n"); return 1; }
    CB = chan_make(4);
    csp_go(&prod, 0);
    csp_go(&cons, 0);
    if csp_sched() != 0 { print("sched fail\n"); return 1; }
    print("sum="); print_i64(SUM); print("\n");
    print("dead="); print_i64(CSP_DEAD); print("\n");
    return 0;
}
MO

if $MOC c.mo -c c.o 2>err2.txt && bash $LINK c.o -o c >/dev/null 2>&1; then
  timeout 30 ./c > out2.txt 2>&1; RC=$?
  g2() { grep -o "^$1=[-0-9]*" out2.txt | head -1 | cut -d= -f2; }
  ck "$(g2 sum)"  "15" "csp：协程直接 return（不调 csp_exit）仍求和正确"
  ck "$(g2 dead)" "0"  "csp：无死锁"
  ck "$RC"        "0"  "csp：退出码 0"
else
  echo "  ✗ 编译/链接失败"; head -5 err2.txt; FAIL=$((FAIL+3))
fi

echo ""
echo "通过 $PASS / 失败 $FAIL"
[ "$FAIL" -eq 0 ]
