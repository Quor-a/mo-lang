# lf.mo —— 无锁数据结构 + 危险指针（Hazard Pointers）安全内存回收
#
# 概念来源（都不是"惯例"，是有出处的算法）：
#   * Treiber 栈：R. K. Treiber, "Systems Programming: Coping with Parallelism",
#     IBM Research RJ 5118, 1986。
#   * Michael–Scott 队列：M. M. Michael, M. L. Scott,
#     "Simple, Fast, and Practical Non-Blocking and Blocking Concurrent Queue
#     Algorithms", PODC 1996（至今仍是 Java ConcurrentLinkedQueue 的蓝本）。
#   * 危险指针：M. M. Michael, "Hazard Pointers: Safe Memory Reclamation for
#     Lock-Free Objects", IEEE TPDS 15(6), 2004。
#
# 为什么值得单独做：这三条都**没有进任何主流语言的标准库**。
# Java 只在 JDK 内部用它，C++ 只有 boost::lockfree / folly，Rust 只有 crossbeam。
# 危险指针更极端——它是一种**用户态内存回收协议**，主流运行时要么干脆没有
# （Go/Java 有 GC 所以不需要），要么藏在库里。
#
# 需要链接 libatomic（CAS / atomic load / atomic store 由它提供符号）：
#   ./bin/moc prog.mo -c prog.o && bash tools/molink.sh prog.o -o prog
#
# 🔴 设计取舍：节点是**槽位下标**而不是真指针。
#     墨语言没有泛型，也没有方便的堆分配器；用全局数组的槽位下标做链接，
#     head/tail 打成 (tag, idx) 的 64 位字，CAS 一次就能同时比较两者 ——
#     这正是解决 ABA 的标准手法（IBM 标记指针）。
#
# 🔴 已知限制：
#   - 槽位固定 4096 个、线程最多 8 个、每线程 3 个危险指针、64 个待回收槽。
#     超出会返回 -1（响出来），不静默。
#   - LF_CASFAIL / LF_NALLOC / LF_NRETIRE / LF_NRECLAIM 是**非原子**计数器，
#     只作观测用，并发下会少计；不要拿它们当正确性判据。
#   - 不提供无锁的 size()：无锁容器的大小在并发下没有良定义的语义。

import "thread.mo";

extern fn __atomic_load_8(p: ptr, mo: i64) -> i64;
extern fn __atomic_store_8(p: ptr, v: i64, mo: i64) -> i64;
extern fn __atomic_compare_exchange_8(p: ptr, exp: ptr, des: i64, weak: i64,
                                      smo: i64, fmo: i64) -> i32;
extern fn __atomic_add_fetch_8(p: ptr, v: i64, mo: i64) -> i64;
extern fn sched_yield() -> i32;

# ---- 槽位表 ----
#   LF_NEXT[i] 存**纯下标**（不带 tag）；ABA 防护由 head/tail 的 tag 负责。
#   LF_NIL 是空哨兵（= 2^32-1），有效槽位是 0..4095。
var LF_NIL: i64 = 4294967295;
var LF_NSLOT: i64 = 4096;
var LF_NT: i64 = 8;
var LF_NH: i64 = 3;
var LF_NR: i64 = 64;

var LF_NEXT: [4096] i64 = 0;
var LF_VAL: [4096] i64 = 0;
var LF_HEAD: i64 = 0;
var LF_QHEAD: i64 = 0;
var LF_QTAIL: i64 = 0;
var LF_FREE: i64 = 0;

# 危险指针：LF_HP[tid*LF_NH + k] = 正在访问的槽位下标（LF_NIL 表示无）
var LF_HP: [24] i64 = 0;
# 待回收表：LF_RET[tid*LF_NR + i]
var LF_RET: [512] i64 = 0;
var LF_RN: [8] i64 = 0;
var LF_EXP: [8] i64 = 0;
var LF_NATIVE: i64 = 0;

# 观测计数器（非原子，见文件头限制）
var LF_DUAL: i64 = 0;
var LF_CASFAIL: i64 = 0;
var LF_NALLOC: i64 = 0;
var LF_NRETIRE: i64 = 0;
var LF_NRECLAIM: i64 = 0;
var LF_NSTUCK: i64 = 0;      # 因被危险指针保护而没能回收的次数

# LF_NOTAG = 1 时关掉 tag —— 仅用于演示 ABA（见 examples/lfbench.mo）
var LF_NOTAG: i64 = 0;

# 槽位状态机自检（LF_CHK=1 时打开，默认关：热路径不想付这个代价）
#   0=在空闲表  1=在容器里  2=已退役待回收
#   它能抓的是「同一个槽位被两次放进空闲表」这类**不报错、只静默产生环**的错误。
var LF_CHK: i64 = 0;
var LF_ST: [4096] i64 = 0;
var LF_V1: i64 = 0;
var LF_V2: i64 = 0;
var LF_V3: i64 = 0;
var LF_D1: i64 = 0;
var LF_D2: i64 = 0;
var LF_D3: i64 = 0;
var LF_D4: i64 = 0;

# 分步 pop 的暂存（ABA / UAF 演示用，单线程）
var LF_BH: i64 = 0;
var LF_BN: i64 = 0;

# ---- 打包 / 解包 ----
fn lf_ix(h: i64) -> i64 { return h % 4294967296; }
fn lf_tg(h: i64) -> i64 { return h / 4294967296; }

fn lf_mk(t: i64, i: i64) -> i64 {
    if LF_NOTAG == 1 {
        return i;
    }
    return t * 4294967296 + i;
}

fn lf_load(p: ptr) -> i64 { return __atomic_load_8(p, 5); }
fn lf_store(p: ptr, v: i64) -> i64 {
    # 注意：C 系 __atomic_store_n 返回 void，不能写 return __atomic_store_8(...)
    # （mo2x/libc 模式 sed 改名后会被 gcc 拒）。包一层。
    __atomic_store_8(p, v, 5);
    return v;
}

# 🔴 CAS：成功返回 1，失败返回 0（并把实际值写回 LF_EXP[tid]）
#
#   返回值必须 `& 255` 之后再判断 —— 这是本库踩到的最阴的一个坑：
#   `__atomic_compare_exchange_8` 真正返回的是 **bool（1 字节）**，
#   按 SysV ABI 只有 AL 有定义，EAX 的高 24 位是**垃圾**。
#   而墨语言对 `extern ... -> i32` 的调用序列末尾是 `cltq`（按符号位扩展
#   EAX→RAX），于是垃圾被一并带进 RAX：实测失败时拿到的是 199936，
#   `!= 0` 恒真 —— **每一次失败的 CAS 都被当成成功**。
#
#   后果不是"跑不通"，而是：CAS 明明失败了却返回 1，调用方以为自己拿到了
#   那个槽位 → 同一个槽位被两个线程各分配一次 → 空闲链表出现自环。
#   不报错、不崩溃，只是数据静默错乱，且只在并发下发作（单线程常被 eax
#   恰好为 0 掩盖）。实测：4 线程 × 20000 次 CAS 自增，修前 65626/80000。
fn lf_cas(tid: i64, p: ptr, exp: i64, des: i64) -> i64 {
    # libc 模式：sed 把 __atomic_compare_exchange_8 → _n；gcc 即使 -fno-builtin
    # 也识别 __atomic_* 内建（__sync_* 不识别）→ 内联 ldxr/stxr，不拉 libatomic。
    # 🔴 判据 = (r & 255)：内联展开返回干净 bool→int 0/1。
    #    （LF_EXP 双通道判据已废：内建 expected 参数是 bool*（1 字节），
    #     失败回写只写 1 字节，8 字节 LF_EXP[tid] 判据不可靠。）
    let r: i64 = 0;
    if LF_NATIVE == 1 {
        return atomic_cas(p, exp, des);
    }
    LF_EXP[tid] = exp;
    r = __atomic_compare_exchange_8(p, &LF_EXP + tid * 8, des, 0, 5, 5);
    if (r & 255) == 1 {
        return 1;
    }
    return 0;
}
fn lf_protect(tid: i64, k: i64, s: i64) -> i64 {
    return lf_store(&LF_HP + (tid * LF_NH + k) * 8, s);
}

# ---- 初始化 ----
fn lf_init() -> i64 {
    let i: i64 = 0;
    let j: i64 = 0;
    # 🔴 v1.212 原子可用性自检：freestanding（裸 moc x86 产物）下 extern
    #    __atomic_* 未解析 = 静默调空地址，CAS 恒失败/恒假成功。
    #    探测一次真 CAS：不通过就响亮报错退出（syscall 60），绝不带病运行。
    let probe: i64 = 0;
    # 先探原生内建（moc 直发 lock cmpxchg，x86/ARM freestanding 都真原子）
    LF_NATIVE = atomic_cas(&probe, 0, 1);
    if LF_NATIVE == 1 {
        lf_store(&probe, 0);
        return 0;
    }
    lf_store(&probe, 0);
    if lf_cas(0, &probe, 0, 1) != 1 {
        syscall(1, 2, "lf.mo: fatal: CAS 原子指令不可用（extern __atomic_* 未解析，freestanding 产物静默调空）——请用 android_native.sh（gcc 内建路径）构建多线程程序\n", 108, 0, 0, 0);
        syscall(60, 86, 0, 0, 0, 0, 0);
        return 0 - 1;
    }
    lf_store(&probe, 0);
    while i < LF_NSLOT {
        LF_NEXT[i] = i + 1;
        i = i + 1;
    }
    LF_NEXT[LF_NSLOT - 1] = LF_NIL;
    # 槽位 0 留给 Michael-Scott 队列的哨兵节点
    LF_NEXT[0] = LF_NIL;
    lf_store(&LF_FREE, lf_mk(0, 1));
    lf_store(&LF_HEAD, lf_mk(0, LF_NIL));
    lf_store(&LF_QHEAD, lf_mk(0, 0));
    lf_store(&LF_QTAIL, lf_mk(0, 0));
    while j < LF_NT * LF_NH {
        LF_HP[j] = LF_NIL;
        j = j + 1;
    }
    i = 0;
    while i < LF_NT {
        LF_RN[i] = 0;
        i = i + 1;
    }
    LF_CASFAIL = 0;
    LF_NALLOC = 0;
    LF_NRETIRE = 0;
    LF_NRECLAIM = 0;
    LF_NSTUCK = 0;
    return 0;
}

# ---- 槽位分配：从空闲栈弹出（自带危险指针保护）----
fn lf_alloc(tid: i64) -> i64 {
    let h: i64 = 0;
    let s: i64 = 0;
    let nx: i64 = 0;
    let nt: i64 = 0;
    let nd: i64 = 0;
    while 1 {
        h = lf_load(&LF_FREE);
        s = lf_ix(h);
        if s == LF_NIL {
            return -1;
        }
        lf_protect(tid, 2, s);
        if lf_load(&LF_FREE) == h {
            nx = lf_load(&LF_NEXT + s * 8);
            nt = lf_tg(h) + 1;
            nd = lf_mk(nt, nx);
            if lf_cas(tid, &LF_FREE, h, nd) == 1 {
                lf_protect(tid, 2, LF_NIL);
                LF_NALLOC = LF_NALLOC + 1;
                if LF_CHK == 1 {
                    if LF_ST[s] != 0 {
                        LF_V1 = LF_V1 + 1;
                        if LF_D1 == 0 {
                            LF_D1 = s;
                            LF_D2 = LF_ST[s];
                            LF_D3 = lf_ix(lf_load(&LF_HEAD));
                            LF_D4 = LF_NEXT[s];
                        }
                    }
                    LF_ST[s] = 1;
                }
                return s;
            }
        }
        lf_protect(tid, 2, LF_NIL);
    }
    return -1;
}

# 把槽位还回空闲栈
fn lf_release(tid: i64, s: i64) -> i64 {
    let h: i64 = 0;
    while 1 {
        h = lf_load(&LF_FREE);
        LF_NEXT[s] = lf_ix(h);
        if lf_cas(tid, &LF_FREE, h, lf_mk(lf_tg(h) + 1, s)) == 1 {
            if LF_CHK == 1 {
                if LF_ST[s] != 2 { LF_V3 = LF_V3 + 1; }
                LF_ST[s] = 0;
            }
            return 0;
        }
    }
    return 0;
}

# ---- 退役 + 扫描回收（危险指针的核心）----
var LF_NORETIRE: i64 = 0;
fn lf_retire(tid: i64, s: i64) -> i64 {
    let n: i64 = 0;
    if LF_NORETIRE == 1 { return 0; }
    n = LF_RN[tid];
    if n >= LF_NR {
        return -1;
    }
    LF_RET[tid * LF_NR + n] = s;
    LF_RN[tid] = n + 1;
    LF_NRETIRE = LF_NRETIRE + 1;
    if LF_RN[tid] >= LF_NR {
        lf_scan(tid);
    }
    return 0;
}

# 扫描：不在任何危险指针里的槽位才能回收
fn lf_scan(tid: i64) -> i64 {
    let i: i64 = 0;
    let n: i64 = 0;
    let s: i64 = 0;
    let j: i64 = 0;
    let k: i64 = 0;
    let hit: i64 = 0;
    n = LF_RN[tid];
    i = 0;
    k = 0;
    while i < n {
        s = LF_RET[tid * LF_NR + i];
        hit = 0;
        j = 0;
        while j < LF_NT * LF_NH {
            if lf_load(&LF_HP + j * 8) == s {
                hit = 1;
            }
            j = j + 1;
        }
        if hit == 0 {
            lf_release(tid, s);
            LF_NRECLAIM = LF_NRECLAIM + 1;
        } else {
            LF_RET[tid * LF_NR + k] = s;
            k = k + 1;
            LF_NSTUCK = LF_NSTUCK + 1;
        }
        i = i + 1;
    }
    LF_RN[tid] = k;
    return k;
}

# 强制把本线程待回收表里能回收的都回收掉
fn lf_flush(tid: i64) -> i64 {
    return lf_scan(tid);
}

# ---- Treiber 栈 ----
fn lf_spush(tid: i64, v: i64) -> i64 {
    let s: i64 = 0;
    let h: i64 = 0;
    s = lf_alloc(tid);
    if s < 0 {
        return -1;
    }
    LF_VAL[s] = v;
    while 1 {
        h = lf_load(&LF_HEAD);
        LF_NEXT[s] = lf_ix(h);
        if lf_cas(tid, &LF_HEAD, h, lf_mk(lf_tg(h) + 1, s)) == 1 {
            return s;
        }
    }
    return -1;
}

# 返回槽位下标（-1 = 空）。调用方读 LF_VAL[s] 之后必须 lf_retire。
fn lf_spop(tid: i64) -> i64 {
    let h: i64 = 0;
    let s: i64 = 0;
    let nx: i64 = 0;
    while 1 {
        h = lf_load(&LF_HEAD);
        s = lf_ix(h);
        if s == LF_NIL {
            return -1;
        }
        lf_protect(tid, 0, s);
        if lf_load(&LF_HEAD) == h {
            nx = lf_load(&LF_NEXT + s * 8);
            if lf_cas(tid, &LF_HEAD, h, lf_mk(lf_tg(h) + 1, nx)) == 1 {
                lf_protect(tid, 0, LF_NIL);
                if LF_CHK == 1 {
                    if LF_ST[s] != 1 { LF_V2 = LF_V2 + 1; }
                    LF_ST[s] = 2;
                }
                return s;
            }
        }
        lf_protect(tid, 0, LF_NIL);
    }
    return -1;
}

# ⚠ 不保护的 pop —— **只用于演示 ABA / UAF**，生产代码不要用。
fn lf_spop_raw() -> i64 {
    let h: i64 = 0;
    let s: i64 = 0;
    let nx: i64 = 0;
    h = lf_load(&LF_HEAD);
    s = lf_ix(h);
    if s == LF_NIL {
        return -1;
    }
    nx = lf_load(&LF_NEXT + s * 8);
    if lf_cas(0, &LF_HEAD, h, lf_mk(lf_tg(h) + 1, nx)) == 1 {
        return s;
    }
    return -1;
}

# 分步 pop：begin 读 head+next，commit 才 CAS —— 中间留出的窗口就是 ABA 的窗口
fn lf_pop_begin() -> i64 {
    let h: i64 = 0;
    let s: i64 = 0;
    h = lf_load(&LF_HEAD);
    s = lf_ix(h);
    if s == LF_NIL {
        return -1;
    }
    LF_BH = h;
    LF_BN = lf_load(&LF_NEXT + s * 8);
    return s;
}

# 带保护的分步 pop（与 lf_pop_begin 对照，用于 UAF 演示）
fn lf_pop_beginP(tid: i64) -> i64 {
    let h: i64 = 0;
    let s: i64 = 0;
    h = lf_load(&LF_HEAD);
    s = lf_ix(h);
    if s == LF_NIL {
        return -1;
    }
    lf_protect(tid, 1, s);
    LF_BH = h;
    LF_BN = lf_load(&LF_NEXT + s * 8);
    return s;
}

fn lf_unprotectP(tid: i64) -> i64 {
    return lf_protect(tid, 1, LF_NIL);
}

fn lf_pop_commit() -> i64 {
    return lf_cas(0, &LF_HEAD, LF_BH, lf_mk(lf_tg(LF_BH) + 1, LF_BN));
}

fn lf_sempty() -> i64 {
    if lf_ix(lf_load(&LF_HEAD)) == LF_NIL {
        return 1;
    }
    return 0;
}

# ---- Michael–Scott 队列 ----
fn lf_qpush(tid: i64, v: i64) -> i64 {
    let s: i64 = 0;
    let t: i64 = 0;
    let nx: i64 = 0;
    let ti: i64 = 0;
    s = lf_alloc(tid);
    if s < 0 {
        return -1;
    }
    LF_VAL[s] = v;
    LF_NEXT[s] = LF_NIL;
    while 1 {
        t = lf_load(&LF_QTAIL);
        ti = lf_ix(t);
        lf_protect(tid, 0, ti);
        if lf_load(&LF_QTAIL) == t {
            nx = lf_load(&LF_NEXT + ti * 8);
            if nx == LF_NIL {
                if lf_cas(tid, &LF_NEXT + ti * 8, LF_NIL, s) == 1 {
                    lf_protect(tid, 0, LF_NIL);
                    # 推进 tail 失败无所谓：别的线程会帮它推进（算法的关键性质）
                    lf_cas(tid, &LF_QTAIL, t, lf_mk(lf_tg(t) + 1, s));
                    return s;
                }
            } else {
                lf_cas(tid, &LF_QTAIL, t, lf_mk(lf_tg(t) + 1, nx));
            }
        }
        lf_protect(tid, 0, LF_NIL);
    }
    return -1;
}

# 返回取到的值（>= 0），-1 = 空。
#   取值的时机是**关键**：必须在 CAS 之前、在危险指针保护下读 LF_VAL[next]，
#   因为 CAS 之后 next 变成新哨兵，别的线程可以立刻把它退役回收。
#   旧哨兵由本函数退役 —— 每次出队退役一个，与入队分配一个正好配平。
fn lf_qpop(tid: i64) -> i64 {
    let h: i64 = 0;
    let t: i64 = 0;
    let nx: i64 = 0;
    let hi: i64 = 0;
    let v: i64 = 0;
    while 1 {
        h = lf_load(&LF_QHEAD);
        hi = lf_ix(h);
        lf_protect(tid, 0, hi);
        if lf_load(&LF_QHEAD) == h {
            t = lf_load(&LF_QTAIL);
            nx = lf_load(&LF_NEXT + hi * 8);
            if lf_ix(t) == hi {
                if nx == LF_NIL {
                    lf_protect(tid, 0, LF_NIL);
                    return -1;
                }
                lf_cas(tid, &LF_QTAIL, t, lf_mk(lf_tg(t) + 1, nx));
            } else {
                lf_protect(tid, 1, nx);
                if lf_load(&LF_QHEAD) == h {
                    v = LF_VAL[nx];
                    if lf_cas(tid, &LF_QHEAD, h, lf_mk(lf_tg(h) + 1, nx)) == 1 {
                        lf_protect(tid, 0, LF_NIL);
                        lf_protect(tid, 1, LF_NIL);
                        if LF_CHK == 1 {
                            if LF_ST[hi] != 1 { LF_V2 = LF_V2 + 1; }
                            LF_ST[hi] = 2;
                        }
                        lf_retire(tid, hi);
                        return v;
                    }
                }
                lf_protect(tid, 1, LF_NIL);
            }
        }
        lf_protect(tid, 0, LF_NIL);
    }
    return -1;
}

fn lf_qempty() -> i64 {
    let h: i64 = 0;
    let hi: i64 = 0;
    h = lf_load(&LF_QHEAD);
    hi = lf_ix(h);
    if lf_load(&LF_NEXT + hi * 8) == LF_NIL {
        return 1;
    }
    return 0;
}

# ---- 互斥锁基线（吞吐对照用）----
#   同样的"取槽位 / 填值 / 链接"三步，只是整段加锁。
var MK: [8] i64 = 0;
var MK_NEXT: [4096] i64 = 0;
var MK_VAL: [4096] i64 = 0;
var MK_TOP: i64 = 0;
var MK_FREE: i64 = 0;

fn lf_mkinit() -> i64 {
    let i: i64 = 0;
    while i < LF_NSLOT {
        MK_NEXT[i] = i + 1;
        i = i + 1;
    }
    MK_NEXT[LF_NSLOT - 1] = LF_NIL;
    MK_TOP = LF_NIL;
    MK_FREE = 0;
    return mutex_init(&MK);
}

fn lf_mkpush(v: i64) -> i64 {
    let s: i64 = 0;
    mutex_lock(&MK);
    s = MK_FREE;
    if s == LF_NIL {
        mutex_unlock(&MK);
        return -1;
    }
    MK_FREE = MK_NEXT[s];
    MK_NEXT[s] = MK_TOP;
    MK_TOP = s;
    MK_VAL[s] = v;
    mutex_unlock(&MK);
    return s;
}

fn lf_mkpop() -> i64 {
    let s: i64 = 0;
    mutex_lock(&MK);
    s = MK_TOP;
    if s == LF_NIL {
        mutex_unlock(&MK);
        return -1;
    }
    MK_TOP = MK_NEXT[s];
    MK_NEXT[s] = MK_FREE;
    MK_FREE = s;
    mutex_unlock(&MK);
    return s;
}
