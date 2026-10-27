#!/bin/bash
# selecttest —— CSP 选择结构（select / guarded command）端到端验证
#
# 必须走 molink + libc：ucontext / pthread 在 libc 里。
#
# 判据不是"有没有崩"，而是**具体数字**：
#   漏唤醒 / 重复唤醒 / 值被两个协程同时拿走 都不报错，只表现为数字不对。
HERE=$(cd "$(dirname "$0")/.." && pwd)
MOC="$HERE/bin/moc"; LINK="$HERE/tools/molink.sh"
TMP=/tmp/mosel
rm -rf $TMP && mkdir -p $TMP/lib
cp "$HERE"/lib/*.mo $TMP/lib/
cd $TMP
PASS=0; FAIL=0
ck() { if [ "$1" = "$2" ]; then PASS=$((PASS+1)); echo "  ✓ $3"; else FAIL=$((FAIL+1)); echo "  ✗ $3 (得到 '$1' 想要 '$2')"; fi; }

cat > t.mo <<'MO'
import "io.mo";
import "csp.mo";
import "select.mo";

var CA: i64 = 0;
var CB: i64 = 0;
var C0: i64 = 0;
var C1: i64 = 0;
var ONLYK: i64 = 99;
var ONLYV: i64 = 0;
var DFLT: i64 = 99;
var WK: i64 = 99;
var WV: i64 = 0;
var CLSDK: i64 = 99;
var CLSDV: i64 = 0;

# ---- A：两个 case 都就绪，统计命中分布（公平性） ----
fn fair_fn() -> i64 {
    let i: i64 = 0;
    let k: i64 = 0;
    while i < 100 {
        chan_send(CA, 1);
        chan_send(CB, 2);
        sel_reset();
        sel_case(CA, 1, 0);
        sel_case(CB, 1, 0);
        k = sel_go(0);
        if k == 0 { C0 = C0 + 1; }
        if k == 1 { C1 = C1 + 1; }
        chan_tryrecv(CA);
        chan_tryrecv(CB);
        i = i + 1;
    }
    csp_exit();
    return 0;
}

# ---- B：只有一个就绪，必须命中它 ----
fn only_fn() -> i64 {
    chan_send(CB, 777);
    sel_reset();
    sel_case(CA, 1, 0);
    sel_case(CB, 1, 0);
    ONLYK = sel_go(1);
    ONLYV = sel_val();
    csp_exit();
    return 0;
}

# ---- C：两个都不就绪 + default → 立即返回 -1 ----
fn dflt_fn() -> i64 {
    sel_reset();
    sel_case(CA, 1, 0);
    sel_case(CB, 1, 0);
    DFLT = sel_go(1);
    csp_exit();
    return 0;
}

# ---- D：两个都不就绪、无 default → 阻塞，等后到的那个 ----
fn wait_fn() -> i64 {
    sel_reset();
    sel_case(CA, 1, 0);
    sel_case(CB, 1, 0);
    WK = sel_go(0);
    WV = sel_val();
    csp_exit();
    return 0;
}
fn late_fn() -> i64 {
    usleep(80000);
    chan_send(CB, 4242);
    csp_exit();
    return 0;
}

# ---- E：closed channel 上的 recv case 视为就绪 ----
fn closed_fn() -> i64 {
    sel_reset();
    sel_case(CA, 1, 0);
    sel_case(CB, 1, 0);
    CLSDK = sel_go(0);
    CLSDV = sel_val();
    csp_exit();
    return 0;
}

fn reset(nw: i64) -> i64 {
    CSP_NC = 0; CSP_FIN = 0; CSP_STOP = 0; CSP_DEAD = 0;
    let r: i64 = csp_init(nw);
    sel_init();
    return r;
}

fn scene_a() -> i64 {
    if reset(1) != 0 { return 1; }
    CA = chan_make(4); CB = chan_make(4);
    csp_go(&fair_fn, 0);
    return csp_sched();
}
fn scene_b() -> i64 {
    if reset(1) != 0 { return 1; }
    CA = chan_make(4); CB = chan_make(4);
    csp_go(&only_fn, 0);
    return csp_sched();
}
fn scene_c() -> i64 {
    if reset(1) != 0 { return 1; }
    CA = chan_make(4); CB = chan_make(4);
    csp_go(&dflt_fn, 0);
    return csp_sched();
}
fn scene_d() -> i64 {
    if reset(1) != 0 { return 1; }
    CA = chan_make(4); CB = chan_make(4);
    csp_go(&wait_fn, 0);
    csp_go(&late_fn, 0);
    return csp_sched();
}
fn scene_e() -> i64 {
    if reset(1) != 0 { return 1; }
    CA = chan_make(4); CB = chan_make(4);
    chan_close(CA);
    csp_go(&closed_fn, 0);
    return csp_sched();
}

fn main() -> i64 {
    srand(20251013);
    if scene_a() != 0 { print("A fail\n"); return 1; }
    print("c0="); print_i64(C0); print("\n");
    print("c1="); print_i64(C1); print("\n");
    if scene_b() != 0 { print("B fail\n"); return 1; }
    print("only_k="); print_i64(ONLYK); print("\n");
    print("only_v="); print_i64(ONLYV); print("\n");
    if scene_c() != 0 { print("C fail\n"); return 1; }
    print("dflt="); print_i64(DFLT); print("\n");
    if scene_d() != 0 { print("D fail\n"); return 1; }
    print("w_k="); print_i64(WK); print("\n");
    print("w_v="); print_i64(WV); print("\n");
    if scene_e() != 0 { print("E fail\n"); return 1; }
    print("cl_k="); print_i64(CLSDK); print("\n");
    print("cl_v="); print_i64(CLSDV); print("\n");
    print("dead="); print_i64(CSP_DEAD); print("\n");
    return 0;
}
MO

cat > w.mo <<'MO'
import "io.mo";
import "csp.mo";
import "select.mo";

var CX: i64 = 0;
var CS: i64 = 0;
var CR: i64 = 0;
var GOT: [64] i64 = 0;
var DUP: i64 = 0;
var MIXK: i64 = 99;
var MIXV: i64 = 0;
var MIXD: i64 = 0;

fn prod() -> i64 {
    let i: i64 = 0;
    while i < 20 { chan_send(CX, i); i = i + 1; }
    csp_exit();
    return 0;
}
# 两个消费者各收 10 个：20 个值必须**恰好各被拿一次**
fn cons() -> i64 {
    let i: i64 = 0;
    while i < 10 {
        sel_reset();
        sel_case(CX, 1, 0);
        let k: i64 = sel_go(0);
        let v: i64 = sel_val();
        if GOT[v] == 1 { DUP = DUP + 1; }
        GOT[v] = 1;
        i = i + 1;
    }
    csp_exit();
    return 0;
}

# send / recv 混合 case：CS 容量 2，前两次 send 就绪，第三次必须等 recv
fn mix_fn() -> i64 {
    let k: i64 = 0;
    sel_reset();
    sel_case(CS, 0, 55);
    sel_case(CR, 1, 0);
    k = sel_go(0);
    if k != 0 { MIXD = MIXD + 1; }
    sel_reset();
    sel_case(CS, 0, 66);
    sel_case(CR, 1, 0);
    k = sel_go(0);
    if k != 0 { MIXD = MIXD + 1; }
    sel_reset();
    sel_case(CS, 0, 77);
    sel_case(CR, 1, 0);
    MIXK = sel_go(0);
    MIXV = sel_val();
    csp_exit();
    return 0;
}
fn mix_send() -> i64 {
    usleep(80000);
    chan_send(CR, 999);
    csp_exit();
    return 0;
}

fn main() -> i64 {
    srand(7788);
    # ---- 竞态：3 worker，两消费者抢 20 个值 ----
    if csp_init(3) != 0 { print("init fail\n"); return 1; }
    sel_init();
    CX = chan_make(24);
    csp_go(&cons, 0);
    csp_go(&cons, 0);
    csp_go(&prod, 0);
    if csp_sched() != 0 { print("sched fail\n"); return 1; }
    let i: i64 = 0;
    let n: i64 = 0;
    let s: i64 = 0;
    while i < 20 { if GOT[i] == 1 { n = n + 1; s = s + i; } i = i + 1; }
    print("gotn="); print_i64(n); print("\n");
    print("sum="); print_i64(s); print("\n");
    print("dup="); print_i64(DUP); print("\n");
    print("dead1="); print_i64(CSP_DEAD); print("\n");

    # ---- send/recv 混合 ----
    CSP_NC = 0; CSP_FIN = 0; CSP_STOP = 0; CSP_DEAD = 0;
    if csp_init(1) != 0 { print("init2 fail\n"); return 1; }
    sel_init();
    CS = chan_make(2); CR = chan_make(4);
    csp_go(&mix_fn, 0);
    csp_go(&mix_send, 0);
    if csp_sched() != 0 { print("sched2 fail\n"); return 1; }
    print("mixk="); print_i64(MIXK); print("\n");
    print("mixv="); print_i64(MIXV); print("\n");
    print("mixd="); print_i64(MIXD); print("\n");
    print("dead2="); print_i64(CSP_DEAD); print("\n");
    return 0;
}
MO

echo "== 单 worker：公平性 / 单就绪 / default / 阻塞 / closed =="
if $MOC t.mo -c t.o 2>err1.txt && bash $LINK t.o -o t >/dev/null 2>&1; then
  timeout 20 ./t > out1.txt 2>&1; RC=$?
  cat out1.txt
  [ $RC -ne 0 ] && echo "  (退出码 $RC)"
  g() { grep -o "^$1=[-0-9]*" out1.txt | head -1 | cut -d= -f2; }
  c0=$(g c0); c1=$(g c1)
  tfair=0
  if [ -n "$c0" ] && [ -n "$c1" ] && [ $((c0+c1)) -eq 100 ] && [ "$c0" -gt 0 ] && [ "$c1" -gt 0 ]; then tfair=1; fi
  ck "$tfair" "1" "公平性：两 case 都就绪时都必须有机会命中（c0=$c0 c1=$c1，和=100）"
  ck "$(g only_k)" "1"  "只有一个就绪 → 必命中它（case 1）"
  ck "$(g only_v)" "777" "命中 case 后取到的值"
  ck "$(g dflt)"   "-1" "都不就绪 + default → 立即返回 -1"
  ck "$(g w_k)"    "1"  "阻塞等待：命中后到的 channel（case 1）"
  ck "$(g w_v)"    "4242" "阻塞等待：取到的值"
  ck "$(g cl_k)"   "0"  "closed channel 上的 recv case 视为就绪"
  ck "$(g cl_v)"   "0"  "closed channel 给出零值"
  ck "$(g dead)"   "0"  "无死锁"
else
  echo "  ✗ 编译/链接失败"; head -20 err1.txt; FAIL=$((FAIL+10))
fi

echo "== 多 worker：竞态 / send-recv 混合 =="
if $MOC w.mo -c w.o 2>err2.txt && bash $LINK w.o -o w >/dev/null 2>&1; then
  timeout 20 ./w > out2.txt 2>&1; RC=$?
  cat out2.txt
  [ $RC -ne 0 ] && echo "  (退出码 $RC)"
  g2() { grep -o "^$1=[-0-9]*" out2.txt | head -1 | cut -d= -f2; }
  ck "$(g2 gotn)"  "20" "竞态：20 个值全部被收到"
  ck "$(g2 sum)"   "190" "竞态：0..19 求和"
  ck "$(g2 dup)"   "0"  "竞态：没有任何值被两个协程同时拿走"
  ck "$(g2 dead1)" "0"  "多 worker 无死锁"
  ck "$(g2 mixk)"  "1"  "混合 case：缓冲满后改走 recv"
  ck "$(g2 mixv)"  "999" "混合 case：recv 取到的值"
  ck "$(g2 mixd)"  "0"  "混合 case：前两次必然命中 send"
  ck "$(g2 dead2)" "0"  "混合 case 无死锁"
else
  echo "  ✗ 编译/链接失败"; head -20 err2.txt; FAIL=$((FAIL+8))
fi

echo "通过 $PASS / 失败 $FAIL"
[ $FAIL -eq 0 ]
