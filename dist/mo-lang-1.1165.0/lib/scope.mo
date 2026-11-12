# scope.mo —— 结构化并发（Structured Concurrency / nursery）
#
# ── 概念来源 ────────────────────────────────────────────────
#   Martin Sústrik（libdill / libmill 作者）2016 年提出 "Structured
#   Concurrency"；Nathaniel Smith 在《Notes on structured concurrency,
#   or: Go statement considered harmful》(2018) 里系统化成 "nursery"：
#     · 协程必须有**确定的所有者**
#     · 所有者离开作用域前必须 join 所有子协程
#     · 于是并发的生命周期形状 = 代码的嵌套形状
#   至今的形态分布（这是个"概念"而不是惯例）：
#     · Trio / anyio（Python）的 nursery —— 最完整的实现
#     · Kotlin coroutineScope、Swift withTaskGroup
#     · Java StructuredTaskScope（JEP 453，Java 21 预览）
#     · Go **没有**：`go` 语句仍然存在"协程逃逸"问题（errgroup 是库级补丁）
#     · C/C++ 基本空白
#
# ── 为什么需要它 ────────────────────────────────────────────
#   `csp_go()` 是"发射后不管"：子协程的生命周期与调用方完全脱钩。
#   于是：
#     · 调用方读到的共享状态可能是**半成品**（没人 join）
#     · 一个子协程失败，其它兄弟还在空跑，错误也没人收到
#     · 父协程先退出，子协程变成孤儿继续写共享内存
#   这三条都不是崩溃，是**结果悄悄不对**。
#
# ── 本库的三条不变量 ────────────────────────────────────────
#   1. join：scope 关闭前，所有 spawn 进来的协程必须已经结束
#   2. 取消传播：任一子协程记录错误 → 同 scope 的兄弟全部被取消，
#      错误同时冒泡到父 scope（外层的 close 也拿得到）
#   3. 无孤儿：scope 关闭后 SC_LIVE 必须为 0；从不静默挂住
#
# ── 取消是协作式的，这是刻意的 ──────────────────────────────
#   抢占式取消（直接杀协程）会让协程停在任意一条指令中间，栈与锁的
#   状态不可知。本库与 Go 的 context、Trio 的 cancel scope 一致：
#   取消只是置标记，由被取消方在**取消点**检查 `sc_cancelled()` 后自行
#   退出。代价是：阻塞在 channel 上的协程**不会**被唤醒。所以本库的
#   `sc_recv()` 用 try + yield 轮询，而不是直接 chan_recv()。
#
# 🔴 已知限制
#   - 取消协作式：不检查取消点的协程会跑完（实测给出证据，不粉饰）
#   - 子协程必须以 `sc_exit(v)` 结束，不能用 `csp_exit()` ——
#     否则存活计数不减，close 会走到超时并置 SC_HANG（响出来，不静默挂）
#   - scope 数上限 32，协程槽沿用 CSP_MAXC
#   - 必须 molink + libc

import "io.mo";
import "thread.mo";
import "csp.mo";

var SC_MAXS: i64 = 32;

var SC_N: i64 = 0;                # 已分配的 scope 数（不复用，便于诊断）
var SC_PARENT: [32] i64 = 0;      # 父 scope，0-1 = 根
var SC_PREV: [32] i64 = 0;        # open 时调用者所在的 scope（close 时恢复）
var SC_STATE: [32] i64 = 0;       # 0=未用 1=open 2=closed
var SC_LIVE: [32] i64 = 0;        # 未结束的子协程数
var SC_TOT: [32] i64 = 0;         # 累计 spawn 数
var SC_CANCEL: [32] i64 = 0;
var SC_ERR: [32] i64 = 0;         # 首个错误码（0 = 无）
var SC_OWNER: [32] i64 = 0;       # 拥有者协程槽，0-1 = 主线程
var SC_WAIT: [32] i64 = 0;        # 拥有者正在 join 等待

var SC_CO: [128] i64 = 0;         # 协程槽 → 所属 scope
var SC_CURCO: [128] i64 = 0;      # 协程槽 → 当前 scope（嵌套时变化）
var SC_CURMAIN: i64 = 0;          # 主线程的当前 scope（-1）

var SC_OPEN: i64 = 0;             # 当前 open 的 scope 数（全部正常结束时必须 0）
var SC_ORPHAN: i64 = 0;           # spawn 到已关闭/不存在的 scope
var SC_HANG: i64 = 0;             # close 超时 —— **必须响出来**
var SC_NOEXIT: i64 = 0;           # 协程没走 sc_exit 就结束（靠 close 超时推断）
var SC_NCANCEL: i64 = 0;          # 被取消过的 scope 数
var SC_LK: [8] i64 = 0;
var SC_CAPWAIT: i64 = 60000;      # close 的等待上限（次）；超出置 SC_HANG

# 连错误计数一起清（只在进程开头调用一次）。
fn sc_reset_all() -> i64 {
    SC_ORPHAN = 0;
    SC_HANG = 0;
    SC_NOEXIT = 0;
    SC_NCANCEL = 0;
    return sc_reset();
}

# ------------------------------------------------------------------ 查询
fn sc_cur() -> i64 {
    let me: i64 = csp_self();
    if me >= 0 { return SC_CURCO[me]; }
    return SC_CURMAIN;
}

# ------------------------------------------------------------------ 生命周期
fn sc_reset() -> i64 {
    SC_N = 0;
    SC_OPEN = 0;
    # 🔴 下面四个**故意不在这里清零**。
    #    它们是"错误计数"，跨场景累加才有意义：清零之后最终打印的
    #    只反映最后一个场景，而最后一个场景往往恰好是干净的 ——
    #    于是看起来全绿，实际只验了 1/5。这正是"静默少报"的形状。
    # SC_ORPHAN / SC_HANG / SC_NOEXIT / SC_NCANCEL 只在 sc_reset_all 里清。
    SC_CURMAIN = 0 - 1;
    let i: i64 = 0;
    while i < 32 {
        SC_STATE[i] = 0;
        SC_LIVE[i] = 0;
        SC_TOT[i] = 0;
        SC_CANCEL[i] = 0;
        SC_ERR[i] = 0;
        SC_PARENT[i] = 0 - 1;
        SC_PREV[i] = 0 - 1;
        SC_OWNER[i] = 0 - 1;
        SC_WAIT[i] = 0;
        i = i + 1;
    }
    let j: i64 = 0;
    while j < 128 {
        SC_CO[j] = 0 - 1;
        SC_CURCO[j] = 0 - 1;
        j = j + 1;
    }
    return 0;
}

fn sc_open() -> i64 {
    if SC_N >= SC_MAXS { return 0 - 1; }
    let s: i64 = SC_N;
    SC_N = SC_N + 1;
    let p: i64 = sc_cur();
    SC_PARENT[s] = p;
    SC_PREV[s] = p;
    SC_STATE[s] = 1;
    SC_LIVE[s] = 0;
    SC_TOT[s] = 0;
    SC_CANCEL[s] = 0;
    SC_ERR[s] = 0;
    SC_WAIT[s] = 0;
    SC_OPEN = SC_OPEN + 1;
    let me: i64 = csp_self();
    SC_OWNER[s] = me;
    if me >= 0 { SC_CURCO[me] = s; } else { SC_CURMAIN = s; }
    return s;
}

# 在当前 scope 里 spawn 一个协程。
#
# 🔴 必须 hold → 登记 → start 三步。反过来（先 start 再登记）的话，
#    协程可能在登记完成前就跑完，读到的 SC_CO 是默认值 —— 详见
#    lib/csp.mo 里 csp_go_hold 的注释。
fn sc_go(f: ptr, arg: i64) -> i64 {
    let s: i64 = sc_cur();
    if s < 0 { SC_ORPHAN = SC_ORPHAN + 1; return 0 - 1; }
    if SC_STATE[s] != 1 { SC_ORPHAN = SC_ORPHAN + 1; return 0 - 1; }
    let slot: i64 = csp_go_hold(f, arg);
    if slot < 0 { return 0 - 1; }
    SC_CO[slot] = s;
    SC_CURCO[slot] = s;
    mutex_lock(&SC_LK);
    SC_LIVE[s] = SC_LIVE[s] + 1;
    SC_TOT[s] = SC_TOT[s] + 1;
    mutex_unlock(&SC_LK);
    csp_start(slot);
    return slot;
}

# ------------------------------------------------------------------ 取消 / 错误
# 取消（向下传播）+ 错误（向上冒泡）。
fn sc_mark(s: i64, e: i64) -> i64 {
    if s < 0 { return 0 - 1; }
    mutex_lock(&SC_LK);
    if e != 0 {
        if SC_ERR[s] == 0 { SC_ERR[s] = e; }
    }
    if SC_CANCEL[s] != 1 {
        SC_CANCEL[s] = 1;
        SC_NCANCEL = SC_NCANCEL + 1;
    }
    # 🔴 「向下传播」已删除 —— 它是**死代码**，变异验证证明的：
    #    把这段 12 行的 O(scope) 循环整个去掉，23 项断言**仍然全绿**
    #    （M2 未被捕获）。原因是 sc_cancelled() 遍历的是**完整祖先链**
    #    （u = 当前 scope，沿 SC_PARENT 一路走到根），而 SC_CANCEL[s]
    #    在上面已经置 1 —— 任何后代的祖先链必然包含 s，所以它们本来就
    #    看得到。向下传播想做的事，祖先链遍历已经做完了。
    #    留着测不到又不可达的代码，正是本项目一直在批判的形状
    #    （aio v1.124 删掉过同样形状的一段）。
    #    真正承担"取消穿透嵌套"职责的是 sc_cancelled 的祖先链遍历 ——
    #    变异 M2'（只查自己所在 scope、不上溯）立刻被 scenarios/G 捕获。
    #
    # 向上：父链也记录错误并取消 —— 内层的失败不能在外层被静默吞掉
    let p: i64 = SC_PARENT[s];
    while p >= 0 {
        if e != 0 {
            if SC_ERR[p] == 0 { SC_ERR[p] = e; }
        }
        SC_CANCEL[p] = 1;
        p = SC_PARENT[p];
    }
    mutex_unlock(&SC_LK);
    return 0;
}

fn sc_fail(e: i64) -> i64 {
    let s: i64 = sc_cur();
    return sc_mark(s, e);
}

fn sc_cancel() -> i64 {
    let s: i64 = sc_cur();
    return sc_mark(s, 0);
}

# 取消标记**不加锁读**。
#
# 曾经以为这里加锁会在热循环里形成"锁风暴"、把**设置**取消的那个协程
# 饿死（实测 iter 时好时坏：2 / 14 / 54 / 33022 / 130）。
# 🔴 那个解释是**错的**，被后面的双通道诊断推翻：
#     · 加一条直接读 SC_CANCEL[0] 的对照通道 → 两条通道读数**始终相同**，
#       说明不是可见性/通路问题；
#     · 加时间戳 → 取消在 t=1~2ms 就置上了，所有子协程 t=0~2ms 就启动了，
#       真正的原因是**兄弟跑得太快，在取消到达之前就把 20000 次迭代跑完了**。
#    真正的修法是改判据（见 examples/structconc.mo），不是改这里。
#
# 那还要不要去掉这把锁？A/B 实测（整程序墙钟）：
#     无锁 227 / 229 / 247 ms      加锁 230 / 232 / 256 ms
#   **本例负载下没有可测差别** —— 所以这不是性能修复，是设计选择：
#   取消标记是单调的（0 → 1 不会再变回 0），单个 i64 读本身不需要锁；
#   而取消点是要放进热循环的，让它顺手去抢一把全局互斥量属于自找麻烦。
#   锁只用于 sc_mark 里的传播，那里必须互斥。
fn sc_cancelled() -> i64 {
    let s: i64 = sc_cur();
    if s < 0 { return 0; }
    let r: i64 = 0;
    let u: i64 = s;
    while u >= 0 {
        if SC_CANCEL[u] == 1 { r = 1; }
        u = SC_PARENT[u];
    }
    return r;
}

# ------------------------------------------------------------------ 结束
# 子协程的结束方式。v != 0 视为错误 → 取消兄弟 + 冒泡。
#
# 🔴 不能直接用 csp_exit()：那样存活计数不减，close 会超时。
fn sc_exit(v: i64) -> i64 {
    let me: i64 = csp_self();
    if me < 0 {
        SC_ORPHAN = SC_ORPHAN + 1;
        csp_exit();
        return 0;
    }
    let s: i64 = SC_CO[me];
    if s < 0 { SC_ORPHAN = SC_ORPHAN + 1; }
    if s >= 0 {
        if v != 0 { sc_mark(s, v); }
        let wake: i64 = 0 - 1;
        mutex_lock(&SC_LK);
        SC_LIVE[s] = SC_LIVE[s] - 1;
        if SC_LIVE[s] == 0 {
            if SC_WAIT[s] == 1 {
                if SC_OWNER[s] >= 0 { wake = SC_OWNER[s]; }
            }
        }
        mutex_unlock(&SC_LK);
        # 唤醒必须在锁外：csp_enq 会去拿 worker 的运行队列锁，
        # 与 SC_LK 形成嵌套持锁（本项目在 aio/ioto 上栽过同样的形状）。
        if wake >= 0 { csp_enq(wake); }
    }
    csp_exit();
    return 0;
}

# ------------------------------------------------------------------ join
# 关闭当前 scope：等所有子协程结束，返回首个错误码。
#
# 🔴 绝不静默挂住：等待超过 SC_CAPWAIT 次就置 SC_HANG 并返回 -2。
#    "卡住"是这个项目里最难查的失败形态 —— 它不报错、不退出，
#    只是再也不动。宁可报错也不要挂。
fn sc_close() -> i64 {
    let s: i64 = sc_cur();
    if s < 0 { return 0 - 1; }
    if SC_STATE[s] != 1 { return 0 - 1; }
    let me: i64 = csp_self();
    mutex_lock(&SC_LK);
    SC_WAIT[s] = 1;
    mutex_unlock(&SC_LK);
    let spin: i64 = 0;
    let live: i64 = 1;
    while live != 0 {
        mutex_lock(&SC_LK);
        live = SC_LIVE[s];
        mutex_unlock(&SC_LK);
        if live == 0 { break; }
        if me >= 0 {
            csp_park();              # 由最后一个子协程 enq 唤醒
        } else {
            usleep(150);             # 主线程不是协程，只能等
        }
        spin = spin + 1;
        if spin > SC_CAPWAIT {
            SC_HANG = SC_HANG + 1;
            SC_NOEXIT = SC_NOEXIT + 1;
            break;
        }
    }
    mutex_lock(&SC_LK);
    SC_WAIT[s] = 0;
    SC_STATE[s] = 2;
    SC_OPEN = SC_OPEN - 1;
    let e: i64 = SC_ERR[s];
    mutex_unlock(&SC_LK);
    # 恢复调用者的当前 scope（嵌套的关键：每个 scope 记住自己 open 前的那个）
    if me >= 0 { SC_CURCO[me] = SC_PREV[s]; } else { SC_CURMAIN = SC_PREV[s]; }
    return e;
}

# ------------------------------------------------------------------ 协作式接收
# 取消点：已取消则返回 -2。轮询而不是阻塞 —— 阻塞的协程收不到取消。
fn sc_recv(c: i64) -> i64 {
    while 1 {
        if sc_cancelled() == 1 { return 0 - 2; }
        if chan_tryrecv(c) == 1 { return CSP_TRYV; }
        if CH_CL[c] == 1 { return 0 - 1; }
        csp_yield();
    }
    return 0;
}

fn sc_live() -> i64 {
    let s: i64 = sc_cur();
    if s < 0 { return 0 - 1; }
    return SC_LIVE[s];
}
