# structconc.mo —— 结构化并发示例
#
# 四个场景，每个都打印可核对的数字：
#   A. join：不 join 就读到的是半成品，join 之后才是完整值
#   B. 取消传播：一个子协程失败 → 兄弟**提前停**（迭代数直接给出证据）
#   C. 嵌套：子协程自己再开一个 scope，内层 close 先于外层
#   D. 错误冒泡：内层的失败在外层的 close 里也拿得到，不会被吞掉
#   F. 被测 scope 故意不是 0：把「spawn 不 hold」的竞态窗口砸开
#   G. 取消穿透嵌套：孙协程在内层 scope 里也必须看到外层的取消

import "io.mo";
import "thread.mo";
import "csp.mo";
import "scope.mo";

var NITER: i64 = 200000;
var NCHILD: i64 = 4;

var PART: [16] i64 = 0;
var SUM: i64 = 0;
var PRE: i64 = 0;
var POST1: i64 = 0;
var POST2: i64 = 0;

var ITER: [8] i64 = 0;
var CSEEN: [8] i64 = 0;   # 通过 sc_cancelled() 第一次看到取消的迭代号（-1 = 从没看到）
var ITER_TOT: i64 = 0;

var GPART: [16] i64 = 0;
var GSUM: i64 = 0;
var IERR: i64 = 0;
var OERR: i64 = 0;

var CB: i64 = 0;

# ---------------------------------------------------------------- A. join
fn work_sum() -> i64 {
    let id: i64 = csp_arg();
    let i: i64 = 0;
    while i < 2000 {
        PART[id] = PART[id] + 1;
        i = i + 1;
    }
    sc_exit(0);
    return 0;
}

fn sum_all() -> i64 {
    let t: i64 = 0;
    let i: i64 = 0;
    while i < NCHILD {
        t = t + PART[i];
        i = i + 1;
    }
    return t;
}

fn scene_join() -> i64 {
    sc_reset();
    CSP_NC = 0; CSP_FIN = 0; CSP_STOP = 0; CSP_DEAD = 0;
    if csp_init(4) != 0 { return 1; }
    let s: i64 = sc_open();
    let i: i64 = 0;
    while i < NCHILD {
        PART[i] = 0;
        sc_go(&work_sum, i);
        i = i + 1;
    }
    # 证据：join 之前读一次（预期是半成品）
    PRE = sum_all();
    let e: i64 = sc_close();
    SUM = sum_all();
    if csp_sched() != 0 { return 1; }
    # 「无孤儿」的结构性证据：close 之后再等 200ms，值**不许再变**。
    # 若有子协程逃逸（没被 join 就继续跑），这里就会涨。
    POST1 = sum_all();
    usleep(200000);
    POST2 = sum_all();
    return e;
}

# ---------------------------------------------------------------- B. 取消
fn work_spin() -> i64 {
    let id: i64 = csp_arg();
    let n: i64 = 0;
    while n < NITER {
        # CSEEN 记录"第一次看到取消"的迭代号 —— 这才是可重复的判据。
        # 早期版本断言的是"兄弟提前停了多少"（iter 越小越好），但那个量
        # 由调度时序支配：兄弟完全可能在取消到达之前就跑完了 20000 次
        # 迭代，于是 iter 时好时坏（实测 2 / 14 / 54 / 33022 / 130）。
        # 把 NITER 提到远大于"取消到达所需时间"，断言就变成
        # "每个兄弟最终都收到了取消" —— 与时序无关。
        if sc_cancelled() == 1 {
            if CSEEN[id] == 0 - 1 { CSEEN[id] = n; }
        }
        if CSEEN[id] >= 0 { break; }
        if id == 0 {
            if n == 2 { sc_fail(42); break; }
        }
        n = n + 1;
        if n % 64 == 0 { csp_yield(); }
    }
    ITER[id] = n;
    sc_exit(0);
    return 0;
}

fn scene_cancel() -> i64 {
    sc_reset();
    CSP_NC = 0; CSP_FIN = 0; CSP_STOP = 0; CSP_DEAD = 0;
    if csp_init(4) != 0 { return 1; }
    let s: i64 = sc_open();
    let i: i64 = 0;
    while i < NCHILD {
        ITER[i] = 0;
        CSEEN[i] = 0 - 1;
        sc_go(&work_spin, i);
        i = i + 1;
    }
    let e: i64 = sc_close();
    ITER_TOT = 0;
    let k: i64 = 0;
    while k < NCHILD {
        ITER_TOT = ITER_TOT + ITER[k];
        k = k + 1;
    }
    if csp_sched() != 0 { return 1; }
    return e;
}

# ---------------------------------------------------------------- C. 嵌套
fn grandchild() -> i64 {
    let id: i64 = csp_arg();
    GPART[id] = GPART[id] + 1;
    sc_exit(0);
    return 0;
}

fn child_nest() -> i64 {
    let id: i64 = csp_arg();
    let s: i64 = sc_open();
    let g: i64 = 0;
    while g < 3 {
        sc_go(&grandchild, g);
        g = g + 1;
    }
    IERR = sc_close();
    sc_exit(0);
    return 0;
}

fn scene_nest() -> i64 {
    sc_reset();
    CSP_NC = 0; CSP_FIN = 0; CSP_STOP = 0; CSP_DEAD = 0;
    if csp_init(2) != 0 { return 1; }
    let k: i64 = 0;
    while k < 16 { GPART[k] = 0; k = k + 1; }
    let s: i64 = sc_open();
    sc_go(&child_nest, 0);
    OERR = sc_close();
    GSUM = 0;
    let j: i64 = 0;
    while j < 3 { GSUM = GSUM + GPART[j]; j = j + 1; }
    if csp_sched() != 0 { return 1; }
    return 0;
}

# ---------------------------------------------------------------- D. 错误冒泡
fn grandchild_fail() -> i64 {
    let id: i64 = csp_arg();
    if id == 1 { sc_fail(77); }
    sc_exit(0);
    return 0;
}

fn child_nestfail() -> i64 {
    let s: i64 = sc_open();
    let g: i64 = 0;
    while g < 3 {
        sc_go(&grandchild_fail, g);
        g = g + 1;
    }
    IERR = sc_close();
    sc_exit(0);
    return 0;
}

fn scene_nestfail() -> i64 {
    sc_reset();
    CSP_NC = 0; CSP_FIN = 0; CSP_STOP = 0; CSP_DEAD = 0;
    if csp_init(2) != 0 { return 1; }
    let s: i64 = sc_open();
    sc_go(&child_nestfail, 0);
    OERR = sc_close();
    if csp_sched() != 0 { return 1; }
    return 0;
}

# ---------------------------------------------------------------- E. 协作式 channel
var PIPE: i64 = 0;
var GOT: [16] i64 = 0;
var GN: i64 = 0;

fn prod_sc() -> i64 {
    let i: i64 = 0;
    while i < 6 {
        chan_send(PIPE, 100 + i);
        i = i + 1;
    }
    sc_exit(0);
    return 0;
}

fn cons_sc() -> i64 {
    let i: i64 = 0;
    while i < 6 {
        let v: i64 = sc_recv(PIPE);
        if v == 0 - 2 { break; }     # 被取消
        GOT[i] = v;
        i = i + 1;
    }
    GN = i;
    sc_exit(0);
    return 0;
}

fn scene_chan() -> i64 {
    sc_reset();
    CSP_NC = 0; CSP_FIN = 0; CSP_STOP = 0; CSP_DEAD = 0;
    if csp_init(2) != 0 { return 1; }
    PIPE = chan_make(4);
    let s: i64 = sc_open();
    sc_go(&cons_sc, 0);
    sc_go(&prod_sc, 0);
    let e: i64 = sc_close();
    if csp_sched() != 0 { return 1; }
    return e;
}

# ------------------------------------------------- F. 被测 scope 不是 0
# M1（先 start 再登记）此前**没被捕获**。原因不是它无害，是竞态窗口太窄：
# 子协程必须恰好在"入队之后、SC_CO 登记之前"这几十条指令内跑完。
# 这一场景把窗口砸开：
#   · 子协程体是**空的**（上来就 sc_exit）—— 跑完得最快
#   · 一次 spawn 64 个、重复 5 轮 —— 320 次机会
#   · 被测 scope 先开一个 dummy 占掉 0 —— 于是未登记的默认值 -1 不再是
#     巧合命中（sc_reset 已把 SC_CO 全部置 -1，未登记 → ORPHAN 计数）
# 未登记的话：SC_LIVE[s] 永远减不到 0 → close 走到超时 → SC_HANG++。
var FERR: i64 = 0;
var FS: i64 = 0;
var FNCH: i64 = 0;

fn tiny() -> i64 {
    sc_exit(0);
    return 0;
}

fn scene_shift() -> i64 {
    sc_reset();
    CSP_NC = 0; CSP_FIN = 0; CSP_STOP = 0; CSP_DEAD = 0;
    if csp_init(4) != 0 { return 1; }
    let dummy: i64 = sc_open();      # 占掉 scope 0
    let s: i64 = sc_open();          # 真正被测的 scope ≠ 0
    FS = s;
    let i: i64 = 0;
    while i < 100 { sc_go(&tiny, i); i = i + 1; }
    FNCH = i;
    let e: i64 = sc_close();
    FERR = e;
    let d: i64 = sc_close();         # 关掉 dummy
    if csp_sched() != 0 { return 1; }
    if d != 0 { return 1; }
    return e;
}

# ------------------------------------------------- G. 取消穿透嵌套
# 真正承担"取消穿透嵌套"职责的是 sc_cancelled() 的**祖先链遍历**，
# 不是 sc_mark 里那段向下传播（那段已被证明是死代码，见 scope.mo）。
# 这里给祖先链一条专属断言：孙协程在**内层 scope** 里，失败发生在
# 外层 scope —— 孙协程仍必须看到取消。
var GCSEEN: i64 = 0;   # 负初值不接受表达式（全局 var 只能字面量），在 scene_deep 里置 -1
var GIT: i64 = 0;
var DERR: i64 = 0;

fn gchild_spin() -> i64 {
    let n: i64 = 0;
    while n < 200000 {
        if sc_cancelled() == 1 { if GCSEEN < 0 { GCSEEN = n; } }
        if GCSEEN >= 0 { break; }
        n = n + 1;
        if n % 64 == 0 { csp_yield(); }
    }
    GIT = n;
    sc_exit(0);
    return 0;
}

fn mid_open() -> i64 {
    let g: i64 = sc_open();
    sc_go(&gchild_spin, 0);
    let e: i64 = sc_close();
    sc_exit(e);
    return 0;
}

fn fail_late() -> i64 {
    let k: i64 = 0;
    while k < 5 { csp_yield(); k = k + 1; }
    sc_fail(55);
    sc_exit(55);
    return 0;
}

fn scene_deep() -> i64 {
    sc_reset();
    CSP_NC = 0; CSP_FIN = 0; CSP_STOP = 0; CSP_DEAD = 0;
    if csp_init(4) != 0 { return 1; }
    GCSEEN = 0 - 1;
    let s: i64 = sc_open();
    sc_go(&mid_open, 0);
    sc_go(&fail_late, 0);
    let e: i64 = sc_close();
    DERR = e;
    if csp_sched() != 0 { return 1; }
    return e;
}

# ------------------------------------------------- H. 登记必须先于启动（竞态注入）
# M1（csp_go：先入队、再登记）此前**没被捕获过**。原因不是它无害，是窗口
# 太窄：父协程"入队 → 登记"之间只有几十条指令，而子协程要一次完整的
# 上下文切换才跑得起来 —— 场景 F 的 100 个空体子协程一轮都没砸开。
#
# 这一场景用**锁占住**把窗口强行撑开到 100ms，于是顺序对错变成确定性可测：
#   · hholder 抢到 SC_LK 后睡 100ms
#   · 父协程此时 sc_go(htiny)，登记路径要拿 SC_LK → 被卡住
#   · 正确顺序（hold → 登记 → start）：卡在 start **之前**，子协程还没入队 → 无害
#   · 错误顺序（start → 登记）：子协程已入队并跑完，父协程还在等锁 →
#     sc_exit 读到 SC_CO = -1 → SC_ORPHAN++，且存活计数不减 → close 超时
# 这是"交错注入"：不靠运气撞时序，而是把时序钉死。
var HAHOLD: i64 = 0;
var HERR: i64 = 0;
var HFAIL: i64 = 0;

fn hholder() -> i64 {
    mutex_lock(&SC_LK);
    HAHOLD = 1;
    usleep(100000);
    mutex_unlock(&SC_LK);
    sc_exit(0);
    return 0;
}

fn htiny() -> i64 { sc_exit(0); return 0; }

fn scene_reg() -> i64 {
    sc_reset();
    CSP_NC = 0; CSP_FIN = 0; CSP_STOP = 0; CSP_DEAD = 0;
    if csp_init(4) != 0 { return 1; }
    HAHOLD = 0;
    let s: i64 = sc_open();
    sc_go(&hholder, 0);
    # 等持锁者就位。上界是刻意的：等不到就报错，而不是无限等下去。
    let w: i64 = 0;
    while HAHOLD == 0 { w = w + 1; if w > 200000000 { HFAIL = 1; return 1; } }
    sc_go(&htiny, 0);          # 此刻 SC_LK 被占 → 登记会被卡住
    let e: i64 = sc_close();
    HERR = e;
    if csp_sched() != 0 { return 1; }
    return e;
}

fn main() -> i64 {
    sc_reset_all();
    print("=== A. join ===\n");
    let ea: i64 = scene_join();
    print("pre="); print_i64(PRE); print("\n");
    print("sum="); print_i64(SUM); print("\n");
    print("ea="); print_i64(ea); print("\n");
    print("post1="); print_i64(POST1); print("\n");
    print("post2="); print_i64(POST2); print("\n");

    print("=== B. 取消传播 ===\n");
    let eb: i64 = scene_cancel();
    print("iter="); print_i64(ITER_TOT); print("\n");
    print("full="); print_i64(NITER * NCHILD); print("\n");
    print("eb="); print_i64(eb); print("\n");
    let q: i64 = 0;
    while q < NCHILD {
        print("iter"); print_i64(q); print("="); print_i64(ITER[q]);
        print(" cseen="); print_i64(CSEEN[q]);
        print("\n");
        q = q + 1;
    }

    print("=== C. 嵌套 ===\n");
    scene_nest();
    print("gsum="); print_i64(GSUM); print("\n");
    print("ierr="); print_i64(IERR); print("\n");
    print("oerr="); print_i64(OERR); print("\n");

    print("=== D. 错误冒泡 ===\n");
    scene_nestfail();
    print("ierr="); print_i64(IERR); print("\n");
    print("oerr="); print_i64(OERR); print("\n");

    print("=== E. 协作式 channel ===\n");
    let ee: i64 = scene_chan();
    print("gn="); print_i64(GN); print("\n");
    print("g0="); print_i64(GOT[0]); print("\n");
    print("g5="); print_i64(GOT[5]); print("\n");
    print("ee="); print_i64(ee); print("\n");

    print("=== F. 被测 scope ≠ 0，64 个空体子协程 ×5 轮 ===\n");
    let r: i64 = 0;
    while r < 10 {
        let ef: i64 = scene_shift();
        if ef != 0 { FERR = ef; }
        r = r + 1;
    }
    print("fs="); print_i64(FS); print("\n");
    print("fnch="); print_i64(FNCH); print("\n");
    print("ferr="); print_i64(FERR); print("\n");

    print("=== G. 取消穿透嵌套 ===\n");
    scene_deep();
    print("gseen="); print_i64(GCSEEN); print("\n");
    print("git="); print_i64(GIT); print("\n");
    print("derr="); print_i64(DERR); print("\n");

    print("=== H. 登记必须先于启动（锁占住注入交错）===\n");
    scene_reg();
    print("hhold="); print_i64(HAHOLD); print("\n");
    print("herr="); print_i64(HERR); print("\n");
    print("hfail="); print_i64(HFAIL); print("\n");

    print("=== 诊断 ===\n");
    print("open="); print_i64(SC_OPEN); print("\n");
    print("orphan="); print_i64(SC_ORPHAN); print("\n");
    print("hang="); print_i64(SC_HANG); print("\n");
    print("ncancel="); print_i64(SC_NCANCEL); print("\n");
    print("dead="); print_i64(CSP_DEAD); print("\n");
    return 0;
}
