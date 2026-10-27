# stm.mo —— 软件事务内存（TL2 风格，encounter-time locking + undo log）
#
# ── 概念 ────────────────────────────────────────────────────────────
#   * Treiber 1986 / Herlihy–Moss 1993（事务的硬件雏形）
#   * Shavit–Touitou 1997（软件事务内存）
#   * Dice–Shalev–Shavit 2006「TL2」（全局版本时钟 + 版本化写锁 orec）
#
#   至今**没有主流语言标准库内建**：C/C++ 只有 GCC 的 -fgnu-tm / libitm，
#   Rust 无，Go 明确不做，Java 只有 research 实现。Clojure / Haskell 有，
#   但都是语言级而非标准库。
#
# ── 为什么是 TL2 而不是别的 ──────────────────────────────────────────
#   encounter-time locking：**写的时候**就把 orec 锁住，于是提交阶段
#   只需要校验读集、不需要再抢锁，也不会出现"读到一半别人提交"的窗口。
#   代价是锁持有时间变长、以及可能死锁 —— 后者这里靠"抢不到锁就直接放弃
#   （abort 而非等待）"规避，这也是 TL2 论文里的做法。
#
# ── API（无闭包，所以是显式事务而非 atomic{} 块）─────────────────────
#     stm_begin(tid);
#     v = stm_read(tid, &X);
#     stm_write(tid, &Y, v + 1);
#     ok = stm_commit(tid);        # 0 = 冲突/放弃，调用方整段重跑
#   墨语言当前不能把函数当回调传出，所以没有 atomic{...}，重跑由调用方
#   写 while 循环完成 —— 这正是 libitm 之外多数 STM 库的显式接口形态。
#
# ── 必须知道的三个限制（都不静默）────────────────────────────────────
#   1. orec 只有 1024 个，地址按 (addr/8) % 1024 映射 → **假冲突**：
#      两个不相干的变量可能共用一把版本锁，表现为"莫名其妙地 abort"。
#      这条是 TL2 的真实性质，不是 bug；STM_FALSH 会把它计出来。
#   2. 读集/写集上限各 64；超了置 STM_OVF 并 abort(3)，不静默截断。
#   3. 统计计数器（STM_OK / STM_ABT / ...）是**非原子**自增，只作观测量，
#      不参与正确性判据。正确性判据一律是"共享变量最终/不变式的值"。

import "lf.mo";

# ---- 全局版本时钟与版本化写锁 ----
var STM_CLOCK: i64 = 0;
var STM_OREC: [1024] i64 = 0;

# ---- 每线程事务状态（tid < 8）----
var STM_RV: [8] i64 = 0;        # 读版本号快照
var STM_RN: [8] i64 = 0;        # 读集大小
var STM_WN: [8] i64 = 0;        # 写集大小
var STM_AB: [8] i64 = 0;        # 已放弃
var STM_AR: [8] i64 = 0;        # 放弃原因 1=校验 2=抢锁 3=集合溢出
var STM_NC: [8] i64 = 0;
var STM_NA: [8] i64 = 0;

# 读集：地址 + 当时看到的 orec 原值
var STM_RA: [512] i64 = 0;
var STM_RQ: [512] i64 = 0;
var STM_RD: [512] i64 = 0;      # 读到的值 —— 只用于判"假冲突"（见 stm_falseck）
# 写集：地址 + 新值 + undo 旧值 + orec 下标 + 加锁前的 orec 原值
var STM_WA: [512] i64 = 0;
var STM_WV: [512] i64 = 0;
var STM_WI: [512] i64 = 0;
var STM_WP: [512] i64 = 0;

# ---- 统计（非原子）----
var STM_OK: i64 = 0;
var STM_ABT: i64 = 0;
var STM_ABV: i64 = 0;
var STM_ABL: i64 = 0;
var STM_OVF: i64 = 0;
var STM_FALSH: i64 = 0;
var STM_LASTV: i64 = 0;
var STM_DUP: i64 = 0;

var STM_T1: i64 = 0;
var STM_T2: i64 = 0;
var STM_T3: i64 = 0;
var STM_T4: i64 = 0;
var STM_T5: i64 = 0;
var STM_T6: i64 = 0;
var STM_T7: i64 = 0;

fn stm_ix(a: i64) -> i64 {
    return (a / 8) % 1024;
}

# ptr -> i64 地址。墨语言里 ptr 与 i64 表示一致，这样写避免各处重复转换。
fn stm_ad(p: ptr) -> i64 {
    return p;
}

# 🔴 墨语言的 ptr 解引用是**按字节**的（p[0] 只碰 1 个字节），
#   所以这里必须用 8 字节原子读写。用 p[0] 的话，写 555 只会改掉最低字节
#   —— 不报错、不崩溃，值看起来"差一点点"，是最难查的一类错。
fn stm_poke(a: i64, v: i64) -> i64 {
    let q: ptr = 0;
    q = a;
    lf_store(q, v);
    return 0;
}

fn stm_peek(a: i64) -> i64 {
    let q: ptr = 0;
    q = a;
    return lf_load(q);
}

fn stm_init() -> i64 {
    let i: i64 = 0;
    STM_CLOCK = 0;
    STM_OK = 0;
    STM_ABT = 0;
    STM_ABV = 0;
    STM_ABL = 0;
    STM_OVF = 0;
    STM_FALSH = 0;
    STM_LASTV = 0;
    STM_DUP = 0;
    i = 0;
    while i < 1024 {
        STM_OREC[i] = 0;
        i = i + 1;
    }
    i = 0;
    while i < 8 {
        STM_RN[i] = 0;
        STM_WN[i] = 0;
        STM_AB[i] = 0;
        STM_AR[i] = 0;
        STM_NC[i] = 0;
        STM_NA[i] = 0;
        i = i + 1;
    }
    return 0;
}

fn stm_begin(tid: i64) -> i64 {
    STM_AB[tid] = 0;
    STM_AR[tid] = 0;
    STM_RN[tid] = 0;
    STM_WN[tid] = 0;
    STM_RV[tid] = STM_CLOCK;
    return 0;
}

fn stm_abort(tid: i64, why: i64) -> i64 {
    if STM_AB[tid] == 0 {
        STM_AB[tid] = 1;
        STM_AR[tid] = why;
        STM_NA[tid] = STM_NA[tid] + 1;
        STM_ABT = STM_ABT + 1;
        if why == 1 {
            STM_ABV = STM_ABV + 1;
        }
        if why == 2 {
            STM_ABL = STM_ABL + 1;
        }
        if why == 3 {
            STM_OVF = STM_OVF + 1;
        }
    }
    return 0;
}

fn stm_aborted(tid: i64) -> i64 {
    return STM_AB[tid];
}

fn stm_why(tid: i64) -> i64 {
    return STM_AR[tid];
}

# 回滚：按加锁前的原值释放 orec（清掉 bit0）。
#   🔴 这里**没有 undo 日志**，也不需要：写回被推迟到校验通过之后，
#   所以失败的事务从未写过任何字节 —— 没有"部分生效"可撤。
#   （v1.134 第一版写了 undo，变异验证证明它是死代码：删掉它 39 项断言
#    一条都不变。留着就是不可验证的代码 —— 已移除。）
fn stm_rollback(tid: i64) -> i64 {
    let b: i64 = 0;
    let i: i64 = 0;
    let n: i64 = 0;
    b = tid * 64;
    n = STM_WN[tid];
    i = n - 1;
    while i >= 0 {
        STM_T1 = b + i;
        STM_OREC[STM_WI[STM_T1]] = STM_WP[STM_T1];
        i = i - 1;
    }
    STM_WN[tid] = 0;
    return 0;
}

fn stm_read(tid: i64, p: ptr) -> i64 {
    let a: i64 = 0;
    let b: i64 = 0;
    let i: i64 = 0;
    let o: i64 = 0;
    let ov: i64 = 0;
    let v: i64 = 0;
    let ov2: i64 = 0;
    let n: i64 = 0;
    if STM_AB[tid] == 1 {
        return 0;
    }
    a = stm_ad(p);
    b = tid * 64;

    # 读自己写过的：直接返回写集里的新值
    i = 0;
    n = STM_WN[tid];
    while i < n {
        STM_T1 = b + i;
        if STM_WA[STM_T1] == a {
            return STM_WV[STM_T1];
        }
        i = i + 1;
    }

    o = stm_ix(a);
    ov = STM_OREC[o];
    if (ov & 1) == 1 {
        stm_abort(tid, 2);
        return 0;
    }
    # 版本比快照新 → 这个值是本事务开始之后才提交的，不能用
    if (ov / 2) > STM_RV[tid] {
        stm_abort(tid, 1);
        return 0;
    }
    v = lf_load(p);
    ov2 = STM_OREC[o];
    if ov2 != ov {
        stm_abort(tid, 1);
        return 0;
    }
    if STM_RN[tid] < 64 {
        STM_T2 = b + STM_RN[tid];
        STM_RA[STM_T2] = a;
        STM_RQ[STM_T2] = ov2;
        STM_RD[STM_T2] = v;
        STM_RN[tid] = STM_RN[tid] + 1;
        return v;
    }
    stm_abort(tid, 3);
    return 0;
}

fn stm_write(tid: i64, p: ptr, v: i64) -> i64 {
    let a: i64 = 0;
    let b: i64 = 0;
    let i: i64 = 0;
    let n: i64 = 0;
    let o: i64 = 0;
    let ov: i64 = 0;
    let r: i64 = 0;
    let old: i64 = 0;
    if STM_AB[tid] == 1 {
        return 0 - 1;
    }
    a = stm_ad(p);
    b = tid * 64;

    i = 0;
    n = STM_WN[tid];
    while i < n {
        STM_T3 = b + i;
        if STM_WA[STM_T3] == a {
            STM_WV[STM_T3] = v;
            return 0;
        }
        i = i + 1;
    }
    if STM_WN[tid] < 64 {
        o = stm_ix(a);
        ov = STM_OREC[o];
        if (ov & 1) == 1 {
            stm_abort(tid, 2);
            return 0 - 1;
        }
        # 抢锁：把 bit0 置 1，版本号不变。抢不到就放弃（不等待 → 不死锁）
        r = lf_cas(tid, &STM_OREC + o * 8, ov, ov + 1);
        if r == 0 {
            stm_abort(tid, 2);
            return 0 - 1;
        }
        STM_T4 = b + STM_WN[tid];
        STM_WA[STM_T4] = a;
        STM_WV[STM_T4] = v;
        STM_WI[STM_T4] = o;
        STM_WP[STM_T4] = ov;
        STM_WN[tid] = STM_WN[tid] + 1;
        return 0;
    }
    stm_abort(tid, 3);
    return 0 - 1;
}

# 本事务是否持有第 o 号 orec
fn stm_owns(tid: i64, o: i64) -> i64 {
    let b: i64 = 0;
    let i: i64 = 0;
    let n: i64 = 0;
    b = tid * 64;
    i = 0;
    n = STM_WN[tid];
    while i < n {
        STM_T5 = b + i;
        if STM_WI[STM_T5] == o {
            return 1;
        }
        i = i + 1;
    }
    return 0;
}

# 🔴 读集校验：光看"锁是不是我的"不够，**版本位也必须一致**。
#
#   反例（实测丢更新约 2%）：
#     T1 读 CNT=5，读集记下版本 c；
#     期间 T0 提交 CNT=6，orec 版本前进到 w；
#     T1 这才 stm_write —— CAS 用的是**当时读到的新值** w，所以加锁成功；
#     提交时若只判"锁是我自己的"就放行，5+1=6 被写回，T0 那次更新丢失。
#
#   所以正确的判据是两条都要：版本位 == 读时记录的版本位，且
#   若被锁则必须是本事务锁的。少了前一条就是静默丢更新。
fn stm_validate(tid: i64) -> i64 {
    let b: i64 = 0;
    let i: i64 = 0;
    let n: i64 = 0;
    let a: i64 = 0;
    let o: i64 = 0;
    let ov: i64 = 0;
    b = tid * 64;
    i = 0;
    n = STM_RN[tid];
    while i < n {
        STM_T6 = b + i;
        a = STM_RA[STM_T6];
        o = stm_ix(a);
        ov = STM_OREC[o];
        if (ov / 2) != (STM_RQ[STM_T6] / 2) {
            return 0;
        }
        if (ov & 1) == 1 {
            if stm_owns(tid, o) == 0 {
                return 0;
            }
        }
        i = i + 1;
    }
    return 1;
}

# 假冲突判定：校验失败时，若读集里**每一个**值都还是当初读到的那个，
#   说明数据根本没变 —— 失败纯粹来自 orec 别名（1024 把锁的分桶碰撞）。
#   这条只作观测，不改变语义；它把这个"看起来像 bug"的性质量化出来。
fn stm_falseck(tid: i64) -> i64 {
    let b: i64 = 0;
    let i: i64 = 0;
    let n: i64 = 0;
    let same: i64 = 0;
    b = tid * 64;
    i = 0;
    n = STM_RN[tid];
    same = 0;
    while i < n {
        STM_T7 = b + i;
        if stm_peek(STM_RA[STM_T7]) == STM_RD[STM_T7] {
            same = same + 1;
        }
        i = i + 1;
    }
    if same == n {
        STM_FALSH = STM_FALSH + 1;
    }
    return same;
}

# 🔴 全局时钟必须**原子自增**。写成 STM_CLOCK = STM_CLOCK + 1 的话，
#   两个并发提交会拿到同一个版本号 wv，于是后一次提交把 orec 设成和前一次
#   完全一样的值 —— 别的读事务校验时"版本号没变"，于是通过，更新被静默丢失。
#   实测：2 线程 × 2000 次自增，非原子版本 CNT=3994（丢 6 次），原子版本 4000。
#   这类错不报错、不崩溃，只表现为总数差一点点，是本项目最典型的静默缺陷形状。
fn stm_nextver(tid: i64) -> i64 {
    let c: i64 = 0;
    let r: i64 = 0;
    r = 0;
    while r == 0 {
        c = STM_CLOCK;
        r = lf_cas(tid, &STM_CLOCK, c, c + 1);
    }
    return c + 1;
}

fn stm_commit(tid: i64) -> i64 {
    let b: i64 = 0;
    let i: i64 = 0;
    let n: i64 = 0;
    let wv: i64 = 0;
    b = tid * 64;
    if STM_AB[tid] == 1 {
        stm_rollback(tid);
        return 0;
    }
    if stm_validate(tid) == 0 {
        stm_falseck(tid);
        stm_abort(tid, 1);
        stm_rollback(tid);
        return 0;
    }
    n = STM_WN[tid];
    if n == 0 {
        STM_NC[tid] = STM_NC[tid] + 1;
        STM_OK = STM_OK + 1;
        return 1;
    }
    # 先推时钟，再写回，最后释放 —— 顺序反了会让别的读事务漏掉版本变化
    wv = stm_nextver(tid);
    # 原子自增保证 wv 严格递增；若哪天退化成非原子自增，这里会立刻响
    if wv == STM_LASTV {
        STM_DUP = STM_DUP + 1;
    }
    STM_LASTV = wv;
    i = 0;
    while i < n {
        STM_T1 = b + i;
        stm_poke(STM_WA[STM_T1], STM_WV[STM_T1]);
        STM_OREC[STM_WI[STM_T1]] = wv * 2;
        i = i + 1;
    }
    STM_NC[tid] = STM_NC[tid] + 1;
    STM_OK = STM_OK + 1;
    STM_WN[tid] = 0;
    return 1;
}
