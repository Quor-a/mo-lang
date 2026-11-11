# actor.mo —— Actor 模型 + 监督树（Erlang/OTP 风格）
#
# ── 概念来源 ────────────────────────────────────────────────
#   Actor：Hewitt（1973）；Erlang/OTP 把它工程化，核心是
#     · 状态私有、邮箱串行、消息异步（"shared nothing"）
#     · **let it crash**：出错不就地处理，而是崩溃、由监督者决定怎么办
#   监督树（supervisor tree）：OTP 的核心容错结构 ——
#     · 重启策略 one-for-one / one-for-all / rest-for-one
#     · 重启强度（intensity / period）：窗口内重启超限 → 监督者自己崩，
#       错误继续向上冒（一个系统会"逐级放弃"，而不是无限重启）
#   形态分布（是"概念"不是惯例）：
#     · Erlang/OTP、Akka（Scala）、CAF（C++）有
#     · Go **没有**（errgroup 只覆盖"等待+首个错误"，不重启）
#     · Rust 无内建（actor 库是社区产物）
#
# ── 与 v1.128 的 nursery 是**相反的**两条哲学 ────────────────
#   nursery（lib/scope.mo）：错误冒泡到父，**父负责等待与传播，不重启**；
#     生命周期形状 = 代码的嵌套形状（子不许活过父）。
#   supervisor：错误冒泡到父，**父负责隔离并重启**；子进程崩溃是**正常
#     路径**，父自己也在超限后崩溃上冒。
#   一个"终止"，一个"重启"。两者放在一起才能看清取舍。
#
# ── 本库的三条不变量 ────────────────────────────────────────
#   1. 状态私有：actor 的状态只有它自己写，因此**不需要锁**
#   2. 邮箱串行：一个 actor = 一个协程，消息一条一条处理，永不重入
#      （检测方式：重启时若旧协程仍活着 → ACT_DUP++，这是真 bug）
#   3. 重启强度必须**响出来**：超限置 ACT_SFAIL 并停止重启，
#      绝不静默无限重启（那会把"崩溃循环"伪装成"一直在工作"）
#
# 🔴 已知限制
#   - 重启复用同一个 pid（Erlang 会分配新 pid）。好处是观测连续，
#     代价是"旧 pid 引用"仍指向新 actor —— 已用 ACT_GEN 显式暴露代数。
#   - 重启**沿用旧邮箱**：邮箱里残留的消息会被新 actor 读到。
#     Erlang 会丢弃。本库不丢弃，测试里先让消息处理完再崩溃。
#   - 取消/停止是协作式的（发 ACT_STOPV，由 actor 在收消息处自行退出）。
#   - pid 上限 32、supervisor 8、每个 supervisor 最多 8 个 child。
#   - 必须 molink + libc（ucontext / pthread 在 libc 里）。

import "io.mo";
import "thread.mo";
import "csp.mo";
import "cstd.mo";

# ── 消息编码 ────────────────────────────────────────────────
#   tag 在 2^40 位以上；tag=0 即用户消息，值本身就是 payload。
#   ACT_STOPV 是负数，act_tag() 见到负数一律当 tag=0。
var ACT_B40: i64 = 1099511627776;      # 2^40
var ACT_B20: i64 = 1048576;            # 2^20
var ACT_TEXIT: i64 = 1;                # 退出信号：a=pid, b=reason
# 🔴 全局 var 的初值**不接受表达式也不接受负号**，所以这里先写 0，
#    真正的 -1 在 act_reset() 里赋。忘了调 act_reset 的话它会是 0 ——
#    那会让 worker 见到消息 0 就退出，所以 act_reset 是必须的第一步。
var ACT_STOPV: i64 = 0;                # 停止消息

var STRAT_ONE: i64 = 0;                # one-for-one：只重启失败者
var STRAT_ALL: i64 = 1;                # one-for-all：重启全部
var STRAT_REST: i64 = 2;               # rest-for-one：失败者及其之后

fn act_mk(tag: i64, a: i64, b: i64) -> i64 {
    return tag * ACT_B40 + a * ACT_B20 + b;
}
fn act_tag(m: i64) -> i64 {
    if m < ACT_B40 { return 0; }
    return m / ACT_B40;
}
fn act_a(m: i64) -> i64 { return (m / ACT_B20) % ACT_B20; }
fn act_b(m: i64) -> i64 { return m % ACT_B20; }

# ── actor 表 ────────────────────────────────────────────────
var ACT_LK: [8] i64 = 0;

var ACT_NP: i64 = 0;                   # 已分配 pid 数（不复用）
var ACT_LIVE: i64 = 0;                 # 存活 actor 数
var ACT_MB: [32] i64 = 0;              # 邮箱（channel）
var ACT_FN: [32] i64 = 0;              # 行为函数（重启要用；ptr 存进 i64 槽）
var ACT_STATE: [32] i64 = 0;           # 0=空 1=活 2=已退出
var ACT_GEN: [32] i64 = 0;             # 代数（重启 +1）
var ACT_ST: [32] i64 = 0;              # 私有状态 —— 只有自己写
var ACT_INIT: [32] i64 = 0;            # 初始状态（重启回到这里）
var ACT_BEH: [32] i64 = 0;             # 当前行为号（become）
var ACT_PAR: [32] i64 = 0;             # 父（supervisor 的 pid），-1 = 无
var ACT_IDX: [32] i64 = 0;             # 在父 children 里的下标
var ACT_RS: [32] i64 = 0;              # 退出原因（0 = 正常）
var ACT_MSGN: [32] i64 = 0;            # 处理过的消息数（重启归零）
var ACT_SLOT: [32] i64 = 0;            # 协程槽（诊断）
var ACT_DIAG: [8] i64 = 0;             # 最后一次重启决策 [st,idx,lo,hi,cpid,sn]（诊断）

# ── supervisor 表 ───────────────────────────────────────────
var ACT_SNSUP: i64 = 0;
var ACT_SPID: [8] i64 = 0;             # sup → 自己的 pid
var ACT_SOF: [32] i64 = 0;             # pid → sup（-1 = 不是 supervisor）
var ACT_SCH: [64] i64 = 0;             # sup*8+i → child pid
var ACT_SN: [8] i64 = 0;
var ACT_SS: [8] i64 = 0;               # 策略
var ACT_SI: [8] i64 = 0;               # intensity（窗口内允许重启次数）
var ACT_SPM: [8] i64 = 0;              # period（窗口，毫秒）
var ACT_SRT: [128] i64 = 0;            # sup*16+k → 重启时间戳
var ACT_SRP: [8] i64 = 0;              # 环形写指针
var ACT_SFAIL: [8] i64 = 0;            # 1=强度超限 2=等子进程退出超时
var ACT_SRUN: [8] i64 = 0;             # 1=运行中
var ACT_SMAX: i64 = 8;
var ACT_CMAX: i64 = 8;

# ── 诊断计数（**跨场景累加**，只在 act_reset 里清）────────────
var ACT_DUP: i64 = 0;                  # 重启时旧协程仍活着 —— 串行性被破坏
var ACT_NRS: i64 = 0;                  # 重启次数
var ACT_NOCH: i64 = 0;                 # chan_make 失败（channel 用尽）
var ACT_SFAILN: i64 = 0;               # supervisor 自身失败次数
var ACT_SENDERR: i64 = 0;              # 发到无效邮箱
var ACT_HANG: i64 = 0;                 # join 超时 —— 必须响出来

fn act_reset() -> i64 {
    ACT_STOPV = 0 - 1;
    ACT_NP = 0;
    ACT_LIVE = 0;
    ACT_DUP = 0;
    ACT_NRS = 0;
    ACT_NOCH = 0;
    ACT_SFAILN = 0;
    ACT_SENDERR = 0;
    ACT_HANG = 0;
    ACT_SNSUP = 0;
    let i: i64 = 0;
    while i < 32 {
        ACT_MB[i] = 0;
        ACT_STATE[i] = 0;
        ACT_GEN[i] = 0;
        ACT_ST[i] = 0;
        ACT_INIT[i] = 0;
        ACT_BEH[i] = 0;
        ACT_PAR[i] = 0 - 1;
        ACT_IDX[i] = 0;
        ACT_RS[i] = 0;
        ACT_MSGN[i] = 0;
        ACT_SLOT[i] = 0 - 1;
        ACT_SOF[i] = 0 - 1;
        i = i + 1;
    }
    let s: i64 = 0;
    while s < 8 {
        ACT_SPID[s] = 0 - 1;
        ACT_SN[s] = 0;
        ACT_SS[s] = 0;
        ACT_SI[s] = 0;
        ACT_SPM[s] = 0;
        ACT_SRP[s] = 0;
        ACT_SFAIL[s] = 0;
        ACT_SRUN[s] = 0;
        s = s + 1;
    }
    let j: i64 = 0;
    while j < 64 { ACT_SCH[j] = 0 - 1; j = j + 1; }
    let k: i64 = 0;
    while k < 128 { ACT_SRT[k] = 0; k = k + 1; }
    return 0;
}

# ------------------------------------------------------------------ 身份
# csp_arg() 拿的是 spawn 时传进去的 pid。这样 actor 起来第一件事就
# 知道自己是谁 —— 不依赖任何"start 之前设置、start 之后才被读"的表，
# 于是彻底绕开了 lib/scope.mo 里那个"登记必须先于启动"的竞态。
fn act_self() -> i64 { return csp_arg(); }

# ------------------------------------------------------------------ 收发
fn act_send(pid: i64, m: i64) -> i64 {
    if pid < 0 { ACT_SENDERR = ACT_SENDERR + 1; return 0 - 1; }
    if pid >= 32 { ACT_SENDERR = ACT_SENDERR + 1; return 0 - 1; }
    let r: i64 = chan_send(ACT_MB[pid], m);
    if r < 0 { ACT_SENDERR = ACT_SENDERR + 1; }
    return r;
}

fn act_recv() -> i64 {
    let pid: i64 = act_self();
    return chan_recv(ACT_MB[pid]);
}

# ------------------------------------------------------------------ 私有状态
fn act_bump(n: i64) -> i64 {
    let pid: i64 = act_self();
    ACT_ST[pid] = ACT_ST[pid] + n;
    ACT_MSGN[pid] = ACT_MSGN[pid] + 1;
    return ACT_ST[pid];
}
fn act_state() -> i64 { return ACT_ST[act_self()]; }
fn act_become(b: i64) -> i64 { ACT_BEH[act_self()] = b; return b; }
fn act_beh() -> i64 { return ACT_BEH[act_self()]; }

# ------------------------------------------------------------------ 生命周期
# 分配一个 actor（**不启动**）。与 act_start 分开，是因为 supervisor 要
# 先把全部 children 登记进表，再统一启动 —— 否则先跑起来的那个可能在
# 表还没填完时崩溃，supervisor 查不到它的 idx。
fn act_spawn(f: ptr, st: i64, par: i64, idx: i64) -> i64 {
    if ACT_NP >= 32 { return 0 - 1; }
    let pid: i64 = ACT_NP;
    ACT_NP = ACT_NP + 1;
    ACT_FN[pid] = f;
    ACT_INIT[pid] = st;
    ACT_ST[pid] = st;
    ACT_MB[pid] = chan_make(64);
    if ACT_MB[pid] < 0 { ACT_NOCH = ACT_NOCH + 1; return 0 - 1; }
    ACT_STATE[pid] = 1;
    ACT_GEN[pid] = 0;
    ACT_BEH[pid] = 0;
    ACT_PAR[pid] = par;
    ACT_IDX[pid] = idx;
    ACT_RS[pid] = 0;
    ACT_MSGN[pid] = 0;
    ACT_LIVE = ACT_LIVE + 1;
    return pid;
}

fn act_start(pid: i64) -> i64 {
    if pid < 0 { return 0 - 1; }
    if ACT_STATE[pid] != 1 { return 0 - 1; }
    let s: i64 = csp_go(ACT_FN[pid], pid);
    if s < 0 { return 0 - 1; }
    ACT_SLOT[pid] = s;
    return pid;
}

# 重启：状态回到初始值、代数 +1、消息计数归零（"重启 = 重建"）。
# 🔴 若旧协程 state 仍是 1（还活着），说明有两个协程共用一个 pid ——
#    邮箱串行性就此破坏，且不会崩、不会报错。必须计下来。
fn act_restart(pid: i64) -> i64 {
    if ACT_STATE[pid] == 1 { ACT_DUP = ACT_DUP + 1; }
    ACT_GEN[pid] = ACT_GEN[pid] + 1;
    ACT_ST[pid] = ACT_INIT[pid];
    ACT_BEH[pid] = 0;
    ACT_STATE[pid] = 1;
    ACT_MSGN[pid] = 0;
    ACT_RS[pid] = 0;
    ACT_LIVE = ACT_LIVE + 1;
    ACT_NRS = ACT_NRS + 1;
    return act_start(pid);
}

fn act_leave(r: i64) -> i64 {
    let pid: i64 = act_self();
    mutex_lock(&ACT_LK);
    ACT_STATE[pid] = 2;
    ACT_LIVE = ACT_LIVE - 1;
    ACT_RS[pid] = r;
    let par: i64 = ACT_PAR[pid];
    mutex_unlock(&ACT_LK);
    if par >= 0 { act_send(par, act_mk(ACT_TEXIT, pid, r)); }
    return csp_exit();
}

fn act_crash(r: i64) -> i64 { return act_leave(r); }

# ------------------------------------------------------------------ supervisor
fn sup_allalive(sup: i64) -> i64 {
    let i: i64 = 0;
    while i < ACT_SN[sup] {
        if ACT_STATE[ACT_SCH[sup * 8 + i]] != 1 { return 0; }
        i = i + 1;
    }
    return 1;
}

# 从 supervisor 协程内部等待：不能用 usleep（会堵住整个 worker），
# 只能 csp_yield 让出。超时必须置 ACT_SFAIL=2，绝不静默空转。
# 🔴 只等 [lo,hi) —— 与重启区间一致。
#    原版等的是**全部** children：one-for-one / rest-for-one 只停了区间内的，
#    区间外的永远活着 → 这里必然超时 → return -1 → 一个都不重启。
#    症状是**完全静默**：不报错、崩溃不算失败、示例退出码 0，
#    只有 gen/msgn 悄悄保持"没重启过"的样子。
fn sup_waitdead(sup: i64, lo: i64, hi: i64, cap: i64) -> i64 {
    let i: i64 = 0;
    let n: i64 = 0;
    let spin: i64 = 0;
    while 1 {
        n = 0;
        i = lo;
        while i < hi {
            if ACT_STATE[ACT_SCH[sup * 8 + i]] == 1 { n = n + 1; }
            i = i + 1;
        }
        if n == 0 { return 0; }
        spin = spin + 1;
        if spin > cap { ACT_SFAIL[sup] = 2; ACT_SFAILN = ACT_SFAILN + 1; return 0 - 1; }
        csp_yield();
    }
    return 0;
}

# 按策略重启。返回 -1 = 监督者自己失败（强度超限或等死超时）。
fn sup_restart(sup: i64, cpid: i64) -> i64 {
    # ── ① 重启强度：窗口内的重启次数已达上限 → 监督者自己崩 ──
    let now: i64 = clock_ms();
    let per: i64 = ACT_SPM[sup];
    let base: i64 = sup * 16;
    let cnt: i64 = 0;
    let k: i64 = 0;
    while k < 16 {
        let ts: i64 = ACT_SRT[base + k];
        if ts != 0 {
            if now - ts <= per { cnt = cnt + 1; }
        }
        k = k + 1;
    }
    if cnt >= ACT_SI[sup] {
        ACT_SFAIL[sup] = 1;
        ACT_SFAILN = ACT_SFAILN + 1;
        ACT_SRUN[sup] = 0;
        return 0 - 1;
    }
    ACT_SRT[base + ACT_SRP[sup]] = now;
    ACT_SRP[sup] = ACT_SRP[sup] + 1;
    if ACT_SRP[sup] >= 16 { ACT_SRP[sup] = 0; }

    # ── ② 决定重启区间 ──
    let st: i64 = ACT_SS[sup];
    let idx: i64 = ACT_IDX[cpid];
    let lo: i64 = idx;
    let hi: i64 = idx + 1;
    if st == STRAT_ALL { lo = 0; hi = ACT_SN[sup]; }
    if st == STRAT_REST { lo = idx; hi = ACT_SN[sup]; }
    # 诊断：把决策本身记录下来 —— 三个策略必须给出三个不同的区间，
    # 而这个决策此前没有任何观测点（one-for-one/rest-for-one 静默不重启时
    # 无从区分"区间算错"和"重启没生效"）。
    ACT_DIAG[0] = st;
    ACT_DIAG[1] = idx;
    ACT_DIAG[2] = lo;
    ACT_DIAG[3] = hi;
    ACT_DIAG[4] = cpid;
    ACT_DIAG[5] = ACT_SN[sup];

    # ── ③ 区间里**还活着**的必须先停掉再重启（否则一个 pid 两个协程）──
    let i: i64 = lo;
    while i < hi {
        let p: i64 = ACT_SCH[sup * 8 + i];
        if ACT_STATE[p] == 1 { act_send(p, ACT_STOPV); }
        i = i + 1;
    }
    let w: i64 = sup_waitdead(sup, lo, hi, 20000);
    if w < 0 { return 0 - 1; }

    i = lo;
    while i < hi {
        act_restart(ACT_SCH[sup * 8 + i]);
        i = i + 1;
    }
    return 0;
}

fn act_supmain() -> i64 {
    let pid: i64 = act_self();
    let sup: i64 = ACT_SOF[pid];
    let m: i64 = 0;
    let t: i64 = 0;
    let cp: i64 = 0;
    let r: i64 = 0;
    let ok: i64 = 0;
    while ACT_SRUN[sup] == 1 {
        m = act_recv();
        if m == ACT_STOPV { break; }
        t = act_tag(m);
        if t == ACT_TEXIT {
            cp = act_a(m);
            r = act_b(m);
            if r != 0 {
                ok = sup_restart(sup, cp);
                if ok < 0 { break; }
            }
        }
    }
    let i: i64 = 0;
    while i < ACT_SN[sup] {
        act_send(ACT_SCH[sup * 8 + i], ACT_STOPV);
        i = i + 1;
    }
    return act_leave(0);
}

# ------------------------------------------------------------------ 主线程侧
fn sup_new(strat: i64, inten: i64, per: i64) -> i64 {
    if ACT_SNSUP >= ACT_SMAX { return 0 - 1; }
    let s: i64 = ACT_SNSUP;
    ACT_SNSUP = ACT_SNSUP + 1;
    ACT_SS[s] = strat;
    ACT_SI[s] = inten;
    ACT_SPM[s] = per;
    ACT_SN[s] = 0;
    ACT_SRP[s] = 0;
    ACT_SFAIL[s] = 0;
    ACT_SRUN[s] = 0;
    # 监督者自己也是一个 actor —— 它也归更外层的监督者管（树由此而来）
    let pid: i64 = act_spawn(&act_supmain, 0, 0 - 1, 0);
    ACT_SPID[s] = pid;
    ACT_SOF[pid] = s;
    return s;
}

fn sup_addch(sup: i64, f: ptr, st: i64) -> i64 {
    if sup < 0 { return 0 - 1; }
    let n: i64 = ACT_SN[sup];
    if n >= ACT_CMAX { return 0 - 1; }
    let pid: i64 = act_spawn(f, st, ACT_SPID[sup], n);
    ACT_SCH[sup * 8 + n] = pid;
    ACT_SN[sup] = n + 1;
    return pid;
}

fn sup_child(sup: i64, i: i64) -> i64 { return ACT_SCH[sup * 8 + i]; }

fn sup_start(sup: i64) -> i64 {
    let r: i64 = act_start(ACT_SPID[sup]);
    if r < 0 { return 0 - 1; }
    ACT_SRUN[sup] = 1;
    let i: i64 = 0;
    while i < ACT_SN[sup] {
        act_start(ACT_SCH[sup * 8 + i]);
        i = i + 1;
    }
    return 0;
}

fn sup_stop(sup: i64) -> i64 {
    ACT_SRUN[sup] = 0;
    return act_send(ACT_SPID[sup], ACT_STOPV);
}

# 等所有 child 都活着（崩溃 → 重启完成后回到 1）
fn act_join(cap: i64) -> i64 {
    let spin: i64 = 0;
    while ACT_LIVE > 0 {
        usleep(200);
        spin = spin + 1;
        if spin > cap { ACT_HANG = ACT_HANG + 1; return 0 - 1; }
    }
    return ACT_LIVE;
}

# 等某个 child 的消息计数到 n（超时返回 -1，绝不静默）
fn act_waitmsgn(pid: i64, n: i64, cap: i64) -> i64 {
    let spin: i64 = 0;
    while ACT_MSGN[pid] < n {
        usleep(200);
        spin = spin + 1;
        if spin > cap { return 0 - 1; }
    }
    return 0;
}

# 等到该 supervisor 的全部 child 都活着、且连续稳定若干次
fn act_settle(sup: i64, cap: i64) -> i64 {
    let spin: i64 = 0;
    let run: i64 = 0;
    while spin < cap {
        if sup_allalive(sup) == 1 {
            run = run + 1;
            if run > 20 { return 0; }
        } else { run = 0; }
        usleep(1000);
        spin = spin + 1;
    }
    return 0 - 1;
}
