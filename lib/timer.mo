# timer.mo —— 分层时间轮（Hierarchical Timing Wheel）
#
# ── 概念来源 ──────────────────────────────────────────────────
#   Varghese & Lauck, *Hashed and Hierarchical Timing Wheels*,
#   IEEE/ACM Trans. Networking 5(6):824-834, 1987。
#   至今的形态分布：
#     · Linux 内核 timer wheel（低分辨率定时器，hrtimer 之前）
#     · Netty HashedWheelTimer、Kafka Purgatory、Akka Scheduler
#     · tokio（Rust）也是分层时间轮，6 级
#     · Go 相反：runtime 用**四叉最小堆**（Go 1.10 起），不是轮
#
# ── 为什么是"轮"而不是"堆" ──────────────────────────────────
#     排序数组   插入 O(n)
#     四叉堆     插入 O(log n)     （Go / libuv）
#     时间轮     插入 O(1)         代价：**量化误差** —— 精度 = tick
#   误差是有界且可测的，本库把它量成数字，而不是含糊地说"大约"。
#
# ── 结构 ─────────────────────────────────────────────────────
#   L0：64 槽 × tick ms        （跨度 64·tick）
#   L1：64 槽 × (64·tick) ms   （跨度 4096·tick）
#   tick=16ms → L0 覆盖 1024ms，L1 覆盖 65536ms（约 65 秒）
#   L0 转满一圈时，把 L1 的**下一个槽**级联下放到 L0。
#
# ── 与 select 的关系（本库存在的理由） ──────────────────────
#   tm_after(ms) 返回一个 cap=1 的 channel，ms 后收到一个值。
#   于是 select 的超时**不需要任何新语法**：
#       sel_reset();
#       sel_case(WORK, 1, 0);
#       sel_case(tm_after(500), 1, 0);
#       k = sel_go(0);          # k==1 即超时
#   这正是 Go 的 `case <-time.After(d)`：超时不是 select 的特例，
#   而是一个普通的 channel。cap=1 是**必须**的 —— 定时器线程在 select
#   尚未注册时就可能触发，值必须能留在缓冲里等它来拿。
#
# ── 取消：时间轮相对堆的真正优势 ────────────────────────────
#   四叉堆（Go 的做法）取消要 O(n) 查或惰性删除；时间轮是 O(1) ——
#   前提是链表**双向**，否则摘除要 O(槽长)。所以本库加 TM_PRV[]。
#
#   tm_cancel(c) 的 c 就是 tm_after 返回的 channel（反查表 TM_OF[] 直接
#   定位槽，不需要额外句柄，也不需要指针参数）。
#
# 🔴 为什么**必须**能取消（这不是锦上添花）：
#   带超时的 I/O 天然有两个分支：I/O 先就绪 / 超时先到。活下来的那个
#   必须把另一个**取消**，否则后者的定时器到期后会往一个已经被别人
#   复用的 channel 里投递 —— 下一个请求一上来就收到一个"超时"，
#   表现为请求被莫名掐断。这就是**幽灵超时**。
#   而且它只在特定时序下出现：绝大多数请求都正常，很难复现。
#   cancel 与 fire 的竞态由同一把 TM_LK 闭合，两边都只在锁内摘链。
#
# 🔴 已知限制
#   - 精度 = tick（实测给出误差区间，不粉饰）
#   - 单次最大 4095 tick（tick=16 时约 65 秒）；超出时 tm_after 返回 -1 响出来
#   - 定时器线程不是协程，只能走 chan_trysend；目标 channel 必须 cap>=1
#   - channel 是**回收池**而非固定配额：稳态占用 = 峰值并发定时器数
#   - 必须 molink + libc（pthread / usleep 在 libc 里）

import "io.mo";
import "thread.mo";
import "csp.mo";

var TM_TICK: i64 = 16;
var TM_NSLOT: i64 = 64;
var TM_NT: i64 = 256;        # 定时器槽数（索引 1..256，0 = 空）

var TM_HD: [128] i64 = 0;    # 2 级 × 64 槽：链表头
var TM_NXT: [257] i64 = 0;   # 链表 next / 空闲链表
var TM_PRV: [257] i64 = 0;   # 双向链表 prev（O(1) 取消的前提）
var TM_HOM: [257] i64 = 0;   # 该槽当前所在的桶头下标（取消时直接定位）
var TM_EXP: [257] i64 = 0;   # 到期 tick（绝对）
var TM_CH: [257] i64 = 0;    # 目标 channel（0 = 槽空闲）
var TM_LV: [257] i64 = 0;    # 所在级（诊断用）
var TM_SEQ: [257] i64 = 0;   # 世代：槽号会复用，靠它让旧 handle 失效
var TM_GSEQ: i64 = 0;
var TM_OF: [64] i64 = 0;     # channel → 槽 handle 的反查表（O(1) 取消）

var TM_FREE: i64 = 0;
var TM_NOWT: i64 = 0;
var TM_NLIVE: i64 = 0;
var TM_FIRED: i64 = 0;
var TM_MISS: i64 = 0;        # 触发了但 trysend 没成功（缓冲满 / 已关闭）
var TM_OVF: i64 = 0;         # 超范围被拒
var TM_CATCH: i64 = 0;       # 线程被饿死后一次补多个 tick 的次数
var TM_BURST: i64 = 0;       # 单次唤醒里补过的最大 tick 数（正常必须 <=2）
var TM_LASTMS: i64 = 0;      # 最近一次 tick 的名义时刻（补丁：见 tm_after）
var TM_CNCL: i64 = 0;        # 成功取消的次数（在到期前摘掉）
var TM_LATE: i64 = 0;        # cancel 时发现已触发/已取消（迟了一步）
var TM_DRN: i64 = 0;         # 归还 channel 时排空掉的值数 —— 幽灵超时的证据
var TM_PC: [64] i64 = 0;     # channel 回收池
var TM_PN: i64 = 0;

var TM_RUN: i64 = 0;
var TM_TID: [8] i64 = 0;
var TM_LK: [8] i64 = 0;
var TM_NEXTMS: i64 = 0;

# 定时器线程自己的时钟缓冲 —— 绝不能共用 cstd 的 TS_SEC/TS_NSEC：
# 协程与定时器线程会并发写同一对全局，结果是时刻互相覆盖。
var TMC: [2] i64 = 0;

fn tm_clock() -> i64 {
    syscall(228, 1, &TMC, 0, 0, 0, 0);
    return TMC[0] * 1000 + TMC[1] / 1000000;
}

# ------------------------------------------------------------------ 槽管理
fn tm_alloc() -> i64 {
    let i: i64 = TM_FREE;
    if i == 0 { return 0; }
    TM_FREE = TM_NXT[i];
    TM_NXT[i] = 0;
    TM_PRV[i] = 0;
    # 槽号会复用，世代让"取消一个早已触发的定时器"变成可判定的：
    # 旧 handle 里的 seq 与当前不符 → 返回 1（迟了），而不是误摘别人的槽。
    TM_GSEQ = TM_GSEQ + 1;
    TM_SEQ[i] = TM_GSEQ;
    TM_NLIVE = TM_NLIVE + 1;
    return i;
}

# 从所在桶的双向链表里摘除。O(1) —— 这是时间轮相对堆的取消优势所在。
fn tm_unlink(i: i64) -> i64 {
    let p: i64 = TM_PRV[i];
    let n: i64 = TM_NXT[i];
    let h: i64 = TM_HOM[i];
    if p == 0 { TM_HD[h] = n; } else { TM_NXT[p] = n; }
    if n != 0 { TM_PRV[n] = p; }
    TM_PRV[i] = 0;
    TM_NXT[i] = 0;
    TM_HOM[i] = 0;
    return 0;
}

fn tm_release(i: i64) -> i64 {
    TM_NXT[i] = TM_FREE;
    TM_FREE = i;
    TM_NLIVE = TM_NLIVE - 1;
    return 0;
}

# 按到期 tick 放进合适的级/槽
fn tm_place(i: i64) -> i64 {
    let d: i64 = TM_EXP[i] - TM_NOWT;
    let lv: i64 = 0;
    let s: i64 = 0;
    let h: i64 = 0;
    if d < 0 { d = 0; }
    if d >= TM_NSLOT {
        lv = 1;
        s = TM_EXP[i] / TM_NSLOT;
        s = s & 63;
    } else {
        s = TM_EXP[i] & 63;
    }
    TM_LV[i] = lv;
    h = lv * TM_NSLOT + s;
    TM_NXT[i] = TM_HD[h];
    TM_PRV[i] = 0;
    if TM_HD[h] != 0 { TM_PRV[TM_HD[h]] = i; }
    TM_HD[h] = i;
    TM_HOM[i] = h;
    return 0;
}

# ------------------------------------------------------------------ 推进一 tick
fn tm_tick() -> i64 {
    let s0: i64 = 0;
    let s1: i64 = 0;
    let h: i64 = 0;
    let i: i64 = 0;
    let nx: i64 = 0;
    let c: i64 = 0;
    let r: i64 = 0;
    # 本 tick 的名义时刻。tm_after 用它补偿"arm 发生在 tick 中间"的零头，
    # 否则定时器相对 arm 时刻可能**提前**最多一个 tick 触发。
    TM_LASTMS = TM_NEXTMS;
    TM_NOWT = TM_NOWT + 1;
    s0 = TM_NOWT & 63;
    # L0 转满一圈 → 把 L1 当前槽下放到 L0
    if s0 == 0 {
        s1 = TM_NOWT / TM_NSLOT;
        s1 = s1 & 63;
        h = TM_NSLOT + s1;
        i = TM_HD[h];
        TM_HD[h] = 0;
        while i != 0 {
            nx = TM_NXT[i];
            tm_place(i);
            i = nx;
        }
    }
    # 触发 L0 当前槽
    h = s0;
    i = TM_HD[h];
    TM_HD[h] = 0;
    while i != 0 {
        nx = TM_NXT[i];
        c = TM_CH[i];
        tm_unlink(i);
        TM_CH[i] = 0;          # 0 = 槽空闲；cancel 靠它判定"已经触发过"
        tm_release(i);
        # 🔴 投递必须在**锁内**完成。放到锁外的话，cancel 可能在
        #    "已摘链但还没 send" 之间抢到锁：它会判定"已触发"于是把
        #    channel 归还池，紧接着这次 send 落进一个已经被别人复用的
        #    channel —— 幽灵超时，而且只在竞态窗口里出现。
        r = chan_trysend(c, 1);
        TM_FIRED = TM_FIRED + 1;
        if r < 1 { TM_MISS = TM_MISS + 1; }
        i = nx;
    }
    return 0;
}

# ------------------------------------------------------------------ 定时器线程
# 🔴 用**绝对时间**推进，不是 usleep(tick) 累加：
#    累加会把每次 usleep 的超睡量累积成漂移，实测 100 tick 后能偏出几十毫秒。
#    这里每次先算出下一个 tick 的绝对时刻再睡到它。
fn tm_threadfn(arg: ptr) -> i64 {
    let now: i64 = 0;
    let gap: i64 = 0;
    let n: i64 = 0;
    TM_NEXTMS = tm_clock() + TM_TICK;
    while TM_RUN == 1 {
        now = tm_clock();
        if now < TM_NEXTMS {
            gap = TM_NEXTMS - now;
            usleep(gap * 1000);
        }
        now = tm_clock();
        n = 0;
        while TM_NEXTMS <= now {
            mutex_lock(&TM_LK);
            tm_tick();
            mutex_unlock(&TM_LK);
            TM_NEXTMS = TM_NEXTMS + TM_TICK;
            n = n + 1;
            if n > TM_BURST { TM_BURST = n; }
            if n > 64 {
                # 线程被饿死太久：不再逐个补，直接跳到当前，记一笔
                TM_CATCH = TM_CATCH + 1;
                TM_NEXTMS = now + TM_TICK;
            }
        }
    }
    return 0;
}

# ------------------------------------------------------------------ 对外接口
fn tm_init(tick: i64) -> i64 {
    let i: i64 = 0;
    if tick > 0 { TM_TICK = tick; }
    i = 1;
    while i <= TM_NT {
        TM_NXT[i] = i + 1;
        i = i + 1;
    }
    TM_NXT[TM_NT] = 0;
    TM_FREE = 1;
    TM_NOWT = 0;
    TM_NLIVE = 0;
    TM_FIRED = 0;
    TM_MISS = 0;
    TM_OVF = 0;
    TM_CATCH = 0;
    TM_BURST = 0;
    TM_CNCL = 0;
    TM_LATE = 0;
    TM_DRN = 0;
    TM_PN = 0;
    TM_GSEQ = 0;
    TM_LASTMS = tm_clock();
    i = 0;
    while i < 128 { TM_HD[i] = 0; i = i + 1; }
    i = 0;
    while i < 64 { TM_OF[i] = 0; i = i + 1; }
    i = 0;
    while i <= TM_NT { TM_PRV[i] = 0; TM_HOM[i] = 0; TM_SEQ[i] = 0; TM_CH[i] = 0; i = i + 1; }
    TM_RUN = 1;
    if thread_create(&TM_TID, &tm_threadfn, 0) != 0 {
        TM_RUN = 0;
        return 0 - 1;
    }
    return 0;
}

fn tm_stop() -> i64 {
    TM_RUN = 0;
    return 0;
}

# ms 毫秒后向返回的 channel 投递一个值。失败返回 -1。
fn tm_after(ms: i64) -> i64 {
    let c: i64 = 0;
    let ticks: i64 = 0;
    let i: i64 = 0;
    let exp: i64 = 0;
    let frac: i64 = 0;
    let now: i64 = 0;
    if TM_RUN == 0 { return 0 - 1; }
    c = tm_take();
    if c < 0 { return 0 - 1; }
    TM_OF[c] = 0;          # 池里的 channel 可能带着上一次的 handle 残留
    if ms <= 0 {
        if chan_trysend(c, 1) < 1 { TM_MISS = TM_MISS + 1; }
        TM_FIRED = TM_FIRED + 1;
        return c;
    }
    ticks = (ms + TM_TICK - 1) / TM_TICK;
    if ticks < 1 { ticks = 1; }
    if ticks >= TM_NSLOT * TM_NSLOT {
        TM_OVF = TM_OVF + 1;
        tm_give(c);        # 已经 take 出来的 channel 必须还回去，否则池越用越小
        return 0 - 1;
    }
    mutex_lock(&TM_LK);
    i = tm_alloc();
    if i == 0 {
        mutex_unlock(&TM_LK);
        TM_OVF = TM_OVF + 1;
        tm_give(c);
        return 0 - 1;
    }
    # 🔴 补偿"arm 落在 tick 中间"的零头 —— 时间轮量化的是**上一个 tick**，
    #    不是 arm 时刻。不补偿的话 50ms 的定时器实际可能 34ms 就触发：
    #    nowt 对应的 tick 已经过去了 frac 毫秒，而 deadline 从那个 tick 起算。
    #    补偿后保证：触发时刻 ∈ [arm+ms, arm+ms+tick)，**绝不提前**。
    now = tm_clock();
    frac = now - TM_LASTMS;
    if frac < 0 { frac = 0; }
    if frac >= TM_TICK { frac = TM_TICK - 1; }
    ticks = (ms + frac + TM_TICK - 1) / TM_TICK;
    if ticks < 1 { ticks = 1; }
    if ticks >= TM_NSLOT * TM_NSLOT {
        # 零头补偿会把 ticks 顶到边界上（4095tick + frac 跨过 4096），
        # 这时必须响出来并归还 channel，不能静默截断成一个短定时。
        TM_OVF = TM_OVF + 1;
        tm_release(i);
        mutex_unlock(&TM_LK);
        tm_give(c);
        return 0 - 1;
    }
    exp = TM_NOWT + ticks;
    TM_EXP[i] = exp;
    TM_CH[i] = c;
    # handle = 槽号 + 世代×1024（槽号 <=256，不重叠）。放进反查表，
    # 于是 tm_cancel 可以直接拿 channel 号定位，不需要额外句柄。
    TM_OF[c] = i + TM_SEQ[i] * 1024;
    tm_place(i);
    mutex_unlock(&TM_LK);
    return c;
}

# ------------------------------------------------------------------ 取消
# 返回 0 = 在到期前成功摘掉（不会再触发）
#      1 = 迟了一步（已触发或已取消过）—— 但 channel 已经归还池
#      -1 = 参数非法
# 两种返回值都会把 channel 归还回收池；区别只是有没有真的拦住触发。
fn tm_cancel(c: i64) -> i64 {
    if c < 0 { return 0 - 1; }
    if c >= 64 { return 0 - 1; }
    mutex_lock(&TM_LK);
    let h: i64 = TM_OF[c];
    if h == 0 {
        mutex_unlock(&TM_LK);
        TM_LATE = TM_LATE + 1;
        return 1;
    }
    let sq: i64 = h / 1024;
    let i: i64 = h - sq * 1024;
    if i < 1 { mutex_unlock(&TM_LK); TM_LATE = TM_LATE + 1; return 1; }
    if i > TM_NT { mutex_unlock(&TM_LK); TM_LATE = TM_LATE + 1; return 1; }
    if TM_SEQ[i] != sq {
        # 槽已被复用 —— 说明这个定时器早就触发过了
        TM_OF[c] = 0;
        mutex_unlock(&TM_LK);
        tm_give(c);
        TM_LATE = TM_LATE + 1;
        return 1;
    }
    if TM_CH[i] != c {
        TM_OF[c] = 0;
        mutex_unlock(&TM_LK);
        tm_give(c);
        TM_LATE = TM_LATE + 1;
        return 1;
    }
    TM_OF[c] = 0;
    tm_unlink(i);
    TM_CH[i] = 0;
    tm_release(i);
    TM_CNCL = TM_CNCL + 1;
    mutex_unlock(&TM_LK);
    tm_give(c);
    return 0;
}

# ------------------------------------------------------------------ channel 回收池
# tm_after 每次都要一个 channel，而 csp 的 channel 总数是有限的（64）。
# 不回收的话：跑几百次带超时的 I/O 之后 chan_make 耗尽 → tm_after 返回 -1
# → 超时分支**静默消失**（那个 case 永远不就绪）。所以回收不是优化，是必需。
fn tm_give(c: i64) -> i64 {
    if c < 0 { return 0; }
    # 🔴 归还前必须排空。这个 channel 里可能还留着上一次的值：
    #    用户没取就取消了，或者 cancel 与 fire 竞态时 fire 抢先一步。
    #    留着它给下一个人，下一个人 arm 完立刻就"超时"了。
    while chan_tryrecv(c) == 1 { TM_DRN = TM_DRN + 1; }
    TM_PC[TM_PN] = c;
    TM_PN = TM_PN + 1;
    return 0;
}

fn tm_take() -> i64 {
    let c: i64 = 0;
    if TM_PN > 0 {
        TM_PN = TM_PN - 1;
        c = TM_PC[TM_PN];
        return c;
    }
    return chan_make(1);
}

fn tm_pool() -> i64 {
    return TM_PN;
}

# ---------- 真实时钟（v1.227）----------
# time_epoch_ms()：Unix 纪元毫秒（CLOCK_REALTIME=0）。
var TMSPEC: [2] i64 = 0;

fn time_epoch_ms() -> i64 {
    syscall(228, 0, &TMSPEC, 0, 0, 0, 0);
    return TMSPEC[0] * 1000 + TMSPEC[1] / 1000000;
}

# civil_from_days（Howard Hinnant 算法）：days 自 1970-01-01 → y/m/d
fn tm_civil(z: ptr, days: i64) -> i64 {
    let d: i64 = days + 719468;
    let era: i64 = 0;
    if d >= 0 { era = d / 146097; } else { era = (d - 146096) / 146097; }
    let doe: i64 = d - era * 146097;
    let yoe: i64 = (doe - doe/1460 + doe/36524 - doe/146096) / 365;
    let y: i64 = yoe + era * 400;
    let doy: i64 = doe - (365*yoe + yoe/4 - yoe/100);
    let mp: i64 = (5*doy + 2) / 153;
    let dd: i64 = doy - (153*mp+2)/5 + 1;
    let mm: i64 = 0;
    if mp < 10 { mm = mp + 3; } else { mm = mp - 9; }
    if mm <= 2 { y = y + 1; }
    store64(z, y); store64(z + 8, mm); store64(z + 16, dd);
    return 0;
}

# time_stamp(dst)：UTC "yyyymmdd-hhmmss"（19+ 字节缓冲）。返回 dst。
var TM_C: [3] i64 = 0;

fn time_stamp(dst: ptr) -> i64 {
    let ms: i64 = time_epoch_ms();
    let secs: i64 = ms / 1000;
    let days: i64 = secs / 86400;
    let sod: i64 = secs % 86400;
    let hh: i64 = sod / 3600;
    let mi: i64 = (sod % 3600) / 60;
    let ss: i64 = sod % 60;
    tm_civil(&TM_C, days);
    # 定宽字段直接拼：y(4) m(2) d(2) - h(2) m(2) s(2)
    let o: i64 = 0;
    let y: i64 = TM_C[0];
    store8(dst + o, 48 + (y / 1000) % 10);
    store8(dst + o + 1, 48 + (y / 100) % 10);
    store8(dst + o + 2, 48 + (y / 10) % 10);
    store8(dst + o + 3, 48 + y % 10);
    store8(dst + o + 4, 48 + (TM_C[1] / 10) % 10);
    store8(dst + o + 5, 48 + TM_C[1] % 10);
    store8(dst + o + 6, 48 + (TM_C[2] / 10) % 10);
    store8(dst + o + 7, 48 + TM_C[2] % 10);
    store8(dst + o + 8, 45);
    store8(dst + o + 9, 48 + (hh / 10) % 10);
    store8(dst + o + 10, 48 + hh % 10);
    store8(dst + o + 11, 48 + (mi / 10) % 10);
    store8(dst + o + 12, 48 + mi % 10);
    store8(dst + o + 13, 48 + (ss / 10) % 10);
    store8(dst + o + 14, 48 + ss % 10);
    store8(dst + o + 15, 0);
    return dst;

    return TM_NOWT;
}
