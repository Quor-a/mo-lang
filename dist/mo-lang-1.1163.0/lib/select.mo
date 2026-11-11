# select.mo —— CSP 的**选择结构**（多选一 / guarded command）
#
# ── 概念来源 ────────────────────────────────────────────────
#   Dijkstra, *Guarded commands, nondeterminacy and formal derivation
#   of programs* (1975)：if 的守卫形式 —— 若干 (guard → statement)，
#   只执行**守卫成立**的其中一条；全不成立则阻塞（若有 else 则走 else）。
#   Hoare 的 CSP (1978) 把它搬进并发：guard 是通信事件。
#   Alef / Plan 9 libthread 的 `alt()`，Go 的 `select {}` 都是它的后裔。
#
#   至今的形态分布：
#     · Go —— 语言级内建
#     · Rust —— tokio::select! / crossbeam::select!（库级宏）
#     · C/C++ —— 无主流内建；libtask(Plan9)、libthread 的 alt() 之外基本空白
#   本库在**无语言支持**的前提下用 ucontext 协程把它实现出来，
#   靠 lib/csp.mo 新增的一个唤醒钩子挂接，不改 csp 的既有语义。
#
# ── 核心难点：一个协程同时等 N 个 channel ────────────────────
#   csp.mo 的等待表 CSP_WCH[] 每协程只有**一个**槽，装不下 N 个 case。
#   所以调度器另开一张多通道表 CSP_SLC[]/CSP_SN[]/CSP_SACT[]/CSP_SWIN[]，
#   select 把自己登记成 ACT=1；csp_wakech() 末尾的 csp_wakesel() 按 channel
#   号反查哪个协程的哪个 case 命中。表放在 csp.mo 是因为唤醒路径只在
#   调度器那一侧 —— 而且墨语言不支持函数指针调用，做不成回调钩子。
#
# 🔴 三个必须闭合的竞态（本文件所有锁的位置都是为这三条服务的）
#   ① 漏唤醒：协程"已注册"却还没 park 时事件到达 —— 唤醒方若直接 enq，
#      协程随后 park 会永远睡着。→ 协程在**锁内**宣告 CSP_ST=7 再 park；
#      唤醒方只在看到 ST==7 时才 enq，否则只置 CSP_SWIN 让它自己重试。
#      （与 lib/aio.mo v1.124 修的是同一类窗口。）
#   ② 重复唤醒 / 值被抢：唤醒只代表"曾经就绪"，不代表现在还能拿到。
#      → 醒来后一律**重新 try 一遍**；失败了清标记再 park。
#   ③ 同一次 select 被多个 case 同时命中：CSP_SWIN 只 claim 一次
#      （ACT 1→2），保证一个协程只被入队一次。
#
# 🔴 已知限制
#   - 每 select 最多 8 个 case；协程数上限与 CSP_MAXC 一致（128）。
#   - 公平性靠**随机起点轮询**（Go 也是随机），单 worker 下可复现。
#   - closed channel 上的 recv case 视为就绪并给出零值（Go 给零值+ok=false）；
#     向 closed channel 的 send case 也视为就绪并置 SEL_ERR（Go 是 panic，
#     墨语言没有 panic，选择"响出来"而不是静默跳过）。
#   - 必须走 molink + libc（ucontext / pthread 在 libc 里）。

import "io.mo";
import "csp.mo";
import "random.mo";

var SEL_OP: [1024] i64 = 0;   # 0 = send, 1 = recv
var SEL_V: [1024] i64 = 0;    # send 的待发值
var SEL_RV: [128] i64 = 0;    # recv 命中的值
var SEL_ERR: i64 = 0;         # 最近一次命中是否是"向已关闭 channel 发送"

# 通道号 / case 数 / 等待状态 存在 csp.mo 的表里（CSP_SLC / CSP_SN /
# CSP_SACT / CSP_SWIN）—— 唤醒路径在调度器那一侧，表必须在那边。

# ------------------------------------------------------------------ 初始化
# 清空 select 等待表。csp.mo 的 csp_wakesel() 会读这些表，
# 全 0 时它什么也不做 —— 不用 select 的程序不受任何影响。
fn sel_init() -> i64 {
    let i: i64 = 0;
    while i < 128 {
        CSP_SN[i] = 0;
        CSP_SACT[i] = 0;
        CSP_SWIN[i] = 0 - 1;
        i = i + 1;
    }
    return 0;
}

# 清空当前协程的 case 列表
fn sel_reset() -> i64 {
    let me: i64 = csp_self();
    if me < 0 { return 0 - 1; }
    CSP_SN[me] = 0;
    CSP_SACT[me] = 0;
    CSP_SWIN[me] = 0 - 1;
    SEL_RV[me] = 0;
    return 0;
}

# 追加一个 case：op=0 发送 v，op=1 接收
fn sel_case(c: i64, op: i64, v: i64) -> i64 {
    let me: i64 = csp_self();
    if me < 0 { return 0 - 1; }
    let n: i64 = CSP_SN[me];
    if n >= CSP_SELK { return 0 - 1; }
    let b: i64 = me * CSP_SELK + n;
    CSP_SLC[b] = c;
    SEL_OP[b] = op;
    SEL_V[b] = v;
    CSP_SN[me] = n + 1;
    return n;
}

fn sel_val() -> i64 {
    let me: i64 = csp_self();
    return SEL_RV[me];
}

# ------------------------------------------------------------------ 尝试单个 case
# 返回 1 = 就绪并完成；0 = 未就绪
fn sel_tryone(me: i64, k: i64) -> i64 {
    let b: i64 = me * CSP_SELK + k;
    let c: i64 = CSP_SLC[b];
    if SEL_OP[b] == 0 {
        let r: i64 = chan_trysend(c, SEL_V[b]);
        if r == 1 { SEL_ERR = 0; return 1; }
        if r == 0 - 1 { SEL_ERR = 1; return 1; }
        return 0;
    }
    let g: i64 = chan_tryrecv(c);
    if g == 1 { SEL_RV[me] = CSP_TRYV; SEL_ERR = 0; return 1; }
    if CH_CL[c] == 1 { SEL_RV[me] = 0; SEL_ERR = 0; return 1; }
    return 0;
}

# ------------------------------------------------------------------ 主入口
# dflt = 1 表示带 default 分支。
# 返回：命中的 case 下标；-1 = 走 default；-2 = 出错 / 非协程上下文。
fn sel_go(dflt: i64) -> i64 {
    let me: i64 = csp_self();
    if me < 0 { return 0 - 2; }
    let n: i64 = CSP_SN[me];
    if n <= 0 {
        if dflt == 1 { return 0 - 1; }
        return 0 - 2;
    }
    let start: i64 = 0;
    if n > 1 { start = rand_range(n); }
    let k: i64 = 0;
    let j: i64 = 0;
    let hit: i64 = 0 - 1;
    SEL_ERR = 0;

    # ---- 阶段一：非阻塞轮询（随机起点 = 多 case 同时就绪时的公平性） ----
    k = 0;
    while k < n {
        j = start + k;
        if j >= n { j = j - n; }
        if hit < 0 {
            if sel_tryone(me, j) == 1 { hit = j; }
        }
        k = k + 1;
    }
    if hit >= 0 { return hit; }
    if dflt == 1 { return 0 - 1; }

    # ---- 阶段二：注册并挂起 ----
    CSP_SACT[me] = 1;
    CSP_SWIN[me] = 0 - 1;
    while 1 {
        k = 0;
        hit = 0 - 1;
        while k < n {
            j = start + k;
            if j >= n { j = j - n; }
            if hit < 0 {
                if sel_tryone(me, j) == 1 { hit = j; }
            }
            k = k + 1;
        }
        if hit >= 0 {
            CSP_SACT[me] = 0;
            CSP_SWIN[me] = 0 - 1;
            return hit;
        }
        mutex_lock(&CSP_SLK);
        if CSP_SWIN[me] >= 0 {
            # 被唤醒过但值被别的协程抢走 → 清标记，立刻重试
            CSP_SWIN[me] = 0 - 1;
            CSP_SACT[me] = 1;
            mutex_unlock(&CSP_SLK);
        } else {
            # 🔴 锁内宣告"我要挂起"，唤醒方才能安全地把我们 enq
            CSP_ST[me] = 7;
            mutex_unlock(&CSP_SLK);
            csp_park();
        }
    }
    return 0 - 2;
}
