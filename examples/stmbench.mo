# stmbench —— 软件事务内存（TL2）端到端验证 + 三个对照
#
# 说明见 docs/stm.md
#
# 用法：
#   ./bin/moc stmbench.mo -c stmbench.o && bash tools/molink.sh stmbench.o -o stmbench
#   ./stmbench
#
# 输出是一组 key=value，tools/stmtest.sh 逐项断言。
#
# ── 判据为什么是这些数字 ────────────────────────────────────────────
#   * 丢失更新：STM 必须**正好** 4000，无保护必须 **< 4000**。
#     两个数都必须出现 —— 只有 STM=4000 说明对照没做，只有 racy 说明 STM 没验。
#   * 转账不变式：两账户总额必须恒为 10000；无保护会漂移。
#   * undo：抢锁失败时，先前已写的位置必须**恢复到原值**，否则事务就不是原子的。
#     这条不崩溃、不报错，只表现为数字不对。

import "stm.mo";
import "thread.mo";
import "io.mo";
import "cstd.mo";

var A: i64 = 0;
var B: i64 = 0;
var CNT: i64 = 0;
var RACY: i64 = 0;
var ACC: [2] i64 = 0;
var RBUF: [128] i64 = 0;
var ALIAS: [1030] i64 = 0;
var OWNC: [8] i64 = 0;
var TH: [64] i64 = 0;
var ARG: [8] i64 = 0;
var NT: i64 = 0;
var OPS: i64 = 0;
var SUM: i64 = 0;
var WTS: [2] i64 = 0;
var MX: [8] i64 = 0;
var BADS: i64 = 0;
var BADR: i64 = 0;

fn now_ms() -> i64 {
    syscall(96, &WTS, 0, 0, 0, 0, 0);
    return WTS[0] * 1000 + WTS[1] / 1000;
}

fn spawn(f: ptr, n: i64) -> i64 {
    let i: i64 = 0;
    i = 0;
    while i < n {
        ARG[i] = i;
        if thread_create(&TH + i * 8, f, &ARG + i * 8) != 0 {
            print("thread_create fail\n");
        }
        i = i + 1;
    }
    return 0;
}

fn join(n: i64) -> i64 {
    let i: i64 = 0;
    i = 0;
    while i < n {
        thread_join(TH[i]);
        i = i + 1;
    }
    return 0;
}

# ---- worker：STM 自增 ----
fn w_inc(arg: ptr) -> i64 {
    let tid: i64 = 0;
    let i: i64 = 0;
    let v: i64 = 0;
    let done: i64 = 0;
    tid = arg[0];
    i = 0;
    while i < OPS {
        done = 0;
        while done == 0 {
            stm_begin(tid);
            v = stm_read(tid, &CNT);
            stm_write(tid, &CNT, v + 1);
            if stm_commit(tid) == 1 {
                done = 1;
            }
        }
        i = i + 1;
    }
    return 0;
}

# ---- worker：无保护自增（对照）----
# 对照：故意把"读"和"写"拉开一点（真实事务里中间必然有别的工作），
#   否则 2 线程下的窗口太窄，可能一次都不丢 —— 那对照就等于没做。
fn w_racy(arg: ptr) -> i64 {
    let i: i64 = 0;
    let v: i64 = 0;
    let k: i64 = 0;
    i = 0;
    while i < OPS {
        v = RACY;
        k = 0;
        while k < 200 {
            v = v + 0;
            k = k + 1;
        }
        RACY = v + 1;
        i = i + 1;
    }
    return 0;
}

# ---- worker：STM 转账（0 -> 1）----
fn w_tx(arg: ptr) -> i64 {
    let tid: i64 = 0;
    let i: i64 = 0;
    let x: i64 = 0;
    let y: i64 = 0;
    let done: i64 = 0;
    tid = arg[0];
    i = 0;
    while i < OPS {
        done = 0;
        while done == 0 {
            stm_begin(tid);
            x = stm_read(tid, &ACC);
            y = stm_read(tid, &ACC + 8);
            if x > 0 {
                stm_write(tid, &ACC, x - 1);
                stm_write(tid, &ACC + 8, y + 1);
            }
            if stm_commit(tid) == 1 {
                done = 1;
            }
        }
        # 不变式检查也放在事务里读：非事务读去读事务数据是未定义的，
        #   可能正好撞见提交写回的中间状态（两个 store 不是原子的）。
        done = 0;
        while done == 0 {
            stm_begin(tid);
            x = stm_read(tid, &ACC);
            y = stm_read(tid, &ACC + 8);
            if stm_commit(tid) == 1 {
                done = 1;
            }
        }
        if x + y != 10000 {
            BADS = BADS + 1;
        }
        i = i + 1;
    }
    return 0;
}

# ---- worker：无保护转账（对照）----
fn w_txr(arg: ptr) -> i64 {
    let i: i64 = 0;
    let v: i64 = 0;
    let k: i64 = 0;
    i = 0;
    while i < OPS {
        v = ACC[0];
        k = 0;
        while k < 200 {
            v = v + 0;
            k = k + 1;
        }
        if v > 0 {
            ACC[0] = v - 1;
            ACC[1] = ACC[1] + 1;
        }
        # 这里用**裸读**：要抓的正是"读到了改一半的状态"
        if ACC[0] + ACC[1] != 10000 {
            BADR = BADR + 1;
        }
        i = i + 1;
    }
    return 0;
}

# ---- worker：互斥锁转账（性能对照）----
fn w_txm(arg: ptr) -> i64 {
    let i: i64 = 0;
    i = 0;
    while i < OPS {
        mutex_lock(&MX);
        if ACC[0] > 0 {
            ACC[0] = ACC[0] - 1;
            ACC[1] = ACC[1] + 1;
        }
        mutex_unlock(&MX);
        i = i + 1;
    }
    return 0;
}

# ============================ 1. 单线程基本正确性 ============================
fn t_seq() -> i64 {
    let v: i64 = 0;
    let ryw: i64 = 0;
    let ok: i64 = 0;
    stm_init();
    A = 10;
    stm_begin(0);
    v = stm_read(0, &A);
    stm_write(0, &A, v + 5);
    ryw = stm_read(0, &A);
    ok = stm_commit(0);
    print("seq v=");
    print_i64(v);
    print(" ryw=");
    print_i64(ryw);
    print(" ok=");
    print_i64(ok);
    print(" a=");
    print_i64(A);
    print_nl();
    return 0;
}

# ============================ 2. 读集校验（确定性）============================
#   T0 读 A，T1 提交 A，T0 再提交必须失败，且 T0 写过的 B 必须回滚。
fn t_conflict() -> i64 {
    let x: i64 = 0;
    let ok0: i64 = 0;
    let ok1: i64 = 0;
    let why: i64 = 0;
    stm_init();
    A = 1000;
    B = 2000;
    stm_begin(0);
    x = stm_read(0, &A);
    stm_begin(1);
    stm_write(1, &A, 99);
    ok1 = stm_commit(1);
    stm_write(0, &B, 7);
    ok0 = stm_commit(0);
    why = stm_why(0);
    print("conflict x=");
    print_i64(x);
    print(" t1=");
    print_i64(ok1);
    print(" t0=");
    print_i64(ok0);
    print(" why=");
    print_i64(why);
    print(" a=");
    print_i64(A);
    print(" b=");
    print_i64(B);
    print_nl();
    return 0;
}

# ============================ 3. 抢锁失败 + undo（确定性）=====================
#   T1 先锁住 B 不提交；T0 写 A 成功、写 B 抢锁失败 → 必须 abort，
#   且 A **必须回滚到原值**。这是"事务原子性"唯一能被数字验证的地方。
fn t_lock() -> i64 {
    let r: i64 = 0;
    let ok0: i64 = 0;
    let why: i64 = 0;
    stm_init();
    A = 1000;
    B = 2000;
    stm_begin(1);
    stm_write(1, &B, 7);
    stm_begin(0);
    stm_write(0, &A, 111);
    r = stm_write(0, &B, 222);
    ok0 = stm_commit(0);
    why = stm_why(0);
    print("lock wrb=");
    print_i64(r);
    print(" t0=");
    print_i64(ok0);
    print(" why=");
    print_i64(why);
    print(" a=");
    print_i64(A);
    print_nl();
    # T1 提交，B 应当变成 7（说明 T0 的回滚没有误伤 T1 的锁）
    stm_commit(1);
    print("lock2 b=");
    print_i64(B);
    print_nl();
    return 0;
}

# ============================ 4. 读集溢出必须响 ==============================
fn t_ovf() -> i64 {
    let i: i64 = 0;
    let ok: i64 = 0;
    let why: i64 = 0;
    stm_init();
    i = 0;
    while i < 128 {
        RBUF[i] = i;
        i = i + 1;
    }
    stm_begin(0);
    i = 0;
    while i < 65 {
        stm_read(0, &RBUF + i * 8);
        i = i + 1;
    }
    ok = stm_commit(0);
    why = stm_why(0);
    print("ovf ok=");
    print_i64(ok);
    print(" why=");
    print_i64(why);
    print(" cnt=");
    print_i64(STM_OVF);
    print_nl();
    return 0;
}

# ==================== 4b. 假冲突（确定性）============================
#   orec 只有 1024 把，相隔 8192 字节的两个地址必然落到同一把版本锁：
#   ALIAS[0] 与 ALIAS[1024] 是**不相干的两份数据**，但一个被提交会让
#   另一个的事务作废。falsh 计数把它量化出来 —— 这是 TL2 的真实性质。
fn t_alias() -> i64 {
    let ok0: i64 = 0;
    let ok1: i64 = 0;
    stm_init();
    stm_begin(0);
    # stm_read 的副作用是把地址记进读集；返回值这里不关心
    stm_read(0, &ALIAS);
    stm_begin(1);
    stm_write(1, &ALIAS + 8192, 42);
    ok1 = stm_commit(1);
    stm_write(0, &ALIAS, 7);
    ok0 = stm_commit(0);
    print("alias ix0=");
    print_i64(stm_ix(stm_ad(&ALIAS)));
    print(" ix1=");
    print_i64(stm_ix(stm_ad(&ALIAS) + 8192));
    print(" t1=");
    print_i64(ok1);
    print(" t0=");
    print_i64(ok0);
    print(" falsh=");
    print_i64(STM_FALSH);
    print(" a0=");
    print_i64(ALIAS[0]);
    print(" a1024=");
    print_i64(ALIAS[1024]);
    print_nl();
    return 0;
}

# ============================ 5. 丢失更新对照 ================================
fn t_lost() -> i64 {
    stm_init();
    CNT = 0;
    RACY = 0;
    OPS = 20000;
    spawn(&w_inc, 2);
    join(2);
    print("lost stm=");
    print_i64(CNT);
    print(" want=");
    print_i64(40000);
    spawn(&w_racy, 2);
    join(2);
    print(" racy=");
    print_i64(RACY);
    print(" stmok=");
    print_i64(STM_OK);
    print(" stmabt=");
    print_i64(STM_ABT);
    print(" abv=");
    print_i64(STM_ABV);
    print(" abl=");
    print_i64(STM_ABL);
    print(" nc01=");
    print_i64(STM_NC[0] + STM_NC[1]);
    print(" dup=");
    print_i64(STM_DUP);
    print_nl();
    return 0;
}

# 单线程对照：若单机也不等于总数，说明是逻辑错而不是并发窗口
fn t_lost1() -> i64 {
    stm_init();
    CNT = 0;
    OPS = 40000;
    spawn(&w_inc, 1);
    join(1);
    print("lost1 stm=");
    print_i64(CNT);
    print(" want=");
    print_i64(40000);
    print(" abv=");
    print_i64(STM_ABV);
    print(" abl=");
    print_i64(STM_ABL);
    print_nl();
    return 0;
}

# ============================ 6. 转账不变式 ==================================
fn t_inv() -> i64 {
    stm_init();
    BADS = 0;
    BADR = 0;
    ACC[0] = 5000;
    ACC[1] = 5000;
    OPS = 1000;
    spawn(&w_tx, 4);
    join(4);
    SUM = ACC[0] + ACC[1];
    print("inv stm=");
    print_i64(SUM);
    print(" bad=");
    print_i64(BADS);
    ACC[0] = 5000;
    ACC[1] = 5000;
    spawn(&w_txr, 4);
    join(4);
    print(" racy=");
    print_i64(ACC[0] + ACC[1]);
    print(" racybad=");
    print_i64(BADR);
    print_nl();
    return 0;
}

# ============================ 6b. 并行提交（各写各的）====================
#   前面的负载里所有事务都争同一把 orec，提交其实是**串行**的，
#   于是"时钟非原子自增"根本不会暴露。这里让 4 个线程各写自己的计数器
#   —— 提交真正并发，非原子自增会给出重复版本号（dup > 0）。
fn w_par(arg: ptr) -> i64 {
    let tid: i64 = 0;
    let i: i64 = 0;
    let v: i64 = 0;
    let done: i64 = 0;
    tid = arg[0];
    i = 0;
    while i < OPS {
        done = 0;
        while done == 0 {
            stm_begin(tid);
            v = stm_read(tid, &OWNC + tid * 8);
            stm_write(tid, &OWNC + tid * 8, v + 1);
            if stm_commit(tid) == 1 {
                done = 1;
            }
        }
        i = i + 1;
    }
    return 0;
}

fn t_par() -> i64 {
    let i: i64 = 0;
    let s: i64 = 0;
    stm_init();
    i = 0;
    while i < 8 {
        OWNC[i] = 0;
        i = i + 1;
    }
    OPS = 10000;
    spawn(&w_par, 4);
    join(4);
    i = 0;
    s = 0;
    while i < 4 {
        s = s + OWNC[i];
        i = i + 1;
    }
    print("par sum=");
    print_i64(s);
    print(" want=");
    print_i64(40000);
    print(" dup=");
    print_i64(STM_DUP);
    print(" abt=");
    print_i64(STM_ABT);
    print_nl();
    return 0;
}


# ============================ 7. STM vs 互斥锁 ================================
fn t_perf() -> i64 {
    let t0: i64 = 0;
    let d1: i64 = 0;
    let d2: i64 = 0;
    stm_init();
    ACC[0] = 200000;
    ACC[1] = 0;
    OPS = 20000;
    t0 = now_ms();
    spawn(&w_tx, 2);
    join(2);
    d1 = now_ms() - t0;
    ACC[0] = 200000;
    ACC[1] = 0;
    t0 = now_ms();
    spawn(&w_txm, 2);
    join(2);
    d2 = now_ms() - t0;
    print("perf stm_ms=");
    print_i64(d1);
    print(" mutex_ms=");
    print_i64(d2);
    print(" sum=");
    print_i64(ACC[0] + ACC[1]);
    print(" abt=");
    print_i64(STM_ABT);
    print(" dup=");
    print_i64(STM_DUP);
    print_nl();
    return 0;
}

fn main() -> i64 {
    t_seq();
    t_conflict();
    t_lock();
    t_ovf();
    t_alias();
    t_lost();
    t_lost1();
    t_inv();
    t_par();
    t_perf();
    print("stat ok=");
    print_i64(STM_OK);
    print(" abt=");
    print_i64(STM_ABT);
    print(" abv=");
    print_i64(STM_ABV);
    print(" abl=");
    print_i64(STM_ABL);
    print(" falsh=");
    print_i64(STM_FALSH);
    print_nl();
    return 0;
}
