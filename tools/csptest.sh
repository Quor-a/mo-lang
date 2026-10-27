#!/bin/bash
# csptest —— CSP 并发（协程调度器 + channel）端到端验证
#
# 必须走 molink + libc：ucontext / pthread 都在 libc 里，裸 moc 产物跑不了。
#
# 判据不是"有没有崩"，而是**具体数字**：
#   channel 漏消息 / 顺序错 / 唤醒失效 都会表现为数字不对，不报错。
HERE=$(cd "$(dirname "$0")/.." && pwd)
MOC="$HERE/bin/moc"; LINK="$HERE/tools/molink.sh"
TMP=/tmp/mocsp
rm -rf $TMP && mkdir -p $TMP/lib
cp "$HERE"/lib/*.mo $TMP/lib/
cd $TMP
PASS=0; FAIL=0
ck() { if [ "$1" = "$2" ]; then PASS=$((PASS+1)); echo "  ✓ $3"; else FAIL=$((FAIL+1)); echo "  ✗ $3 (得到 '$1' 想要 '$2')"; fi; }

cat > t.mo <<'MO'
import "io.mo";
import "csp.mo";

var CB: i64 = 0;          # 缓冲 channel
var CU: i64 = 0;          # 无缓冲 channel
var SUM: i64 = 0;         # 多生产者求和
var RDV: i64 = 0;         # rendezvous 求和
var BLK: i64 = 0;         # 先阻塞的接收者收到的和
var SEQ: [8] i64 = 0;     # FIFO 顺序记录
var SEQN: i64 = 0;
var CLOSED_OK: i64 = 99;
var W2SUM: i64 = 0;

fn prod_many() -> i64 {
    let base: i64 = csp_arg();
    let i: i64 = 0;
    while i < 5 { chan_send(CB, base + i); i = i + 1; }
    csp_exit();
    return 0;
}

fn cons_many() -> i64 {
    let i: i64 = 0;
    while i < 10 {
        let v: i64 = chan_recv(CB);
        SUM = SUM + v;
        i = i + 1;
    }
    csp_exit();
    return 0;
}

# FIFO：单生产者发 0..4，接收者按到达顺序记录
fn prod_seq() -> i64 {
    let i: i64 = 0;
    while i < 5 { chan_send(CB, i); i = i + 1; }
    csp_exit();
    return 0;
}
fn cons_seq() -> i64 {
    let i: i64 = 0;
    while i < 5 {
        let v: i64 = chan_recv(CB);
        SEQ[SEQN] = v;
        SEQN = SEQN + 1;
        i = i + 1;
    }
    csp_exit();
    return 0;
}

# 先阻塞的接收者：cons 先入队，channel 空，必须挂起等生产者
fn cons_first() -> i64 {
    let i: i64 = 0;
    while i < 5 {
        let v: i64 = chan_recv(CB);
        BLK = BLK + v;
        i = i + 1;
    }
    csp_exit();
    return 0;
}

# 无缓冲 rendezvous
fn prod_rdv() -> i64 {
    let i: i64 = 1;
    while i <= 5 { chan_send(CU, i); i = i + 1; }
    csp_exit();
    return 0;
}
fn cons_rdv() -> i64 {
    let i: i64 = 0;
    while i < 5 {
        let v: i64 = chan_recv(CU);
        RDV = RDV + v;
        i = i + 1;
    }
    csp_exit();
    return 0;
}

# 多 worker：4 个生产者各发 3 个
fn prod_w2() -> i64 {
    let base: i64 = csp_arg();
    chan_send(CB, base);
    chan_send(CB, base + 1);
    chan_send(CB, base + 2);
    csp_exit();
    return 0;
}
fn cons_w2() -> i64 {
    let i: i64 = 0;
    while i < 12 {
        let v: i64 = chan_recv(CB);
        W2SUM = W2SUM + v;
        i = i + 1;
    }
    csp_exit();
    return 0;
}

fn csp_reset(nw: i64) -> i64 {
    CSP_NC = 0; CSP_FIN = 0; CSP_STOP = 0; CSP_DEAD = 0;
    return csp_init(nw);
}

fn scene1() -> i64 {
    if csp_reset(1) != 0 { return 1; }
    CB = chan_make(4);
    csp_go(&prod_many, 100);
    csp_go(&prod_many, 200);
    csp_go(&cons_many, 0);
    if csp_sched() != 0 { return 1; }
    return 0;
}

fn scene2() -> i64 {
    if csp_reset(1) != 0 { return 1; }
    CB = chan_make(4);
    csp_go(&prod_seq, 0);
    csp_go(&cons_seq, 0);
    if csp_sched() != 0 { return 1; }
    return 0;
}

fn scene3() -> i64 {
    if csp_reset(1) != 0 { return 1; }
    CB = chan_make(2);
    csp_go(&cons_first, 0);       # 接收者先跑：channel 空，必须阻塞
    csp_go(&prod_seq, 0);
    if csp_sched() != 0 { return 1; }
    return 0;
}

fn scene4() -> i64 {
    if csp_reset(1) != 0 { return 1; }
    CU = chan_make(0);            # 无缓冲
    csp_go(&cons_rdv, 0);
    csp_go(&prod_rdv, 0);
    if csp_sched() != 0 { return 1; }
    # 关闭后再收：CH_OK 必须为 0
    chan_close(CU);
    chan_recv(CU);
    CLOSED_OK = CH_OK;
    return 0;
}

fn main() -> i64 {
    # ---- 场景 1：缓冲 channel，2 生产者 1 消费者 ----
    if scene1() != 0 { print("scene1 fail\n"); return 1; }
    print("sum="); print_i64(SUM); print("\n");

    # ---- 场景 2：FIFO 顺序 ----
    if scene2() != 0 { print("scene2 fail\n"); return 1; }
    let i: i64 = 0;
    let ok: i64 = 1;
    while i < 5 { if SEQ[i] != i { ok = 0; } i = i + 1; }
    print("fifo="); print_i64(ok); print("\n");

    # ---- 场景 3：接收者先阻塞 ----
    BLK = 0;
    if scene3() != 0 { print("scene3 fail\n"); return 1; }
    print("blk="); print_i64(BLK); print("\n");

    # ---- 场景 4：无缓冲 rendezvous + close ----
    if scene4() != 0 { print("scene4 fail\n"); return 1; }
    print("rdv="); print_i64(RDV); print("\n");
    print("closed="); print_i64(CLOSED_OK); print("\n");

    print("dead="); print_i64(CSP_DEAD); print("\n");
    return 0;
}
MO

cat > w2.mo <<'MO'
import "io.mo";
import "csp.mo";
var CB: i64 = 0;
var W2SUM: i64 = 0;
fn prod_w2() -> i64 {
    let base: i64 = csp_arg();
    chan_send(CB, base);
    chan_send(CB, base + 1);
    chan_send(CB, base + 2);
    csp_exit();
    return 0;
}
fn cons_w2() -> i64 {
    let i: i64 = 0;
    while i < 12 {
        let v: i64 = chan_recv(CB);
        W2SUM = W2SUM + v;
        i = i + 1;
    }
    csp_exit();
    return 0;
}
fn main() -> i64 {
    if csp_init(3) != 0 { print("init fail\n"); return 1; }
    CB = chan_make(8);
    csp_go(&cons_w2, 0);
    csp_go(&prod_w2, 10);
    csp_go(&prod_w2, 20);
    csp_go(&prod_w2, 30);
    csp_go(&prod_w2, 40);
    if csp_sched() != 0 { print("sched fail\n"); return 1; }
    print("w2="); print_i64(W2SUM); print("\n");
    print("dead="); print_i64(CSP_DEAD); print("\n");
    return 0;
}
MO

echo "== 单 worker：缓冲 / FIFO / 阻塞 / rendezvous / close =="
if $MOC t.mo -c t.o 2>err1.txt && bash $LINK t.o -o t >/dev/null 2>&1; then
  timeout 30 ./t > out1.txt 2>&1; RC=$?
  cat out1.txt
  [ $RC -ne 0 ] && echo "  (退出码 $RC)"
  g() { grep -o "^$1=[-0-9]*" out1.txt | head -1 | cut -d= -f2; }
  ck "$(g sum)"      "1520" "缓冲 channel：2 生产者求和"
  ck "$(g fifo)"     "1"    "FIFO 顺序（0,1,2,3,4）"
  ck "$(g blk)"      "10"   "接收者先阻塞，不丢消息"
  ck "$(g rdv)"      "15"   "无缓冲 rendezvous 求和"
  ck "$(g closed)"   "0"    "close 后 recv 的 CH_OK"
  ck "$(g dead)"     "0"    "无死锁"
else
  echo "  ✗ 编译/链接失败"; head -5 err1.txt; FAIL=$((FAIL+6))
fi

echo "== 3 worker：跨线程 channel =="
if $MOC w2.mo -c w2.o 2>err2.txt && bash $LINK w2.o -o w2 >/dev/null 2>&1; then
  timeout 30 ./w2 > out2.txt 2>&1; RC=$?
  cat out2.txt
  [ $RC -ne 0 ] && echo "  (退出码 $RC)"
  g2() { grep -o "^$1=[-0-9]*" out2.txt | head -1 | cut -d= -f2; }
  # (10+11+12)+(20+21+22)+(30+31+32)+(40+41+42) = 33+63+93+123 = 312
  ck "$(g2 w2)"   "312" "3 worker 跨线程求和"
  ck "$(g2 dead)" "0"   "多 worker 无死锁"
else
  echo "  ✗ 编译/链接失败"; head -5 err2.txt; FAIL=$((FAIL+2))
fi

echo "通过 $PASS / 失败 $FAIL"
[ $FAIL -eq 0 ]
