# lfbench —— 无锁数据结构基准 + 三个"静默缺陷"的可复现场景
#
# 说明见 docs/lf.md
#
# 用法：
#   ./bin/moc lfbench.mo -c lfbench.o && bash tools/molink.sh lfbench.o -o lfbench
#   ./lfbench [线程数] [每线程操作数]
#
# 输出是一组 key=value，tools/lftest.sh 逐项断言。

import "lf.mo";
import "cstd.mo";

var OPS: i64 = 0;
var NTH: i64 = 0;
var MODE: i64 = 0;          # 0 = 无锁栈  1 = 互斥锁栈  2 = 无锁队列
var TH: [64] i64 = 0;       # pthread_t
var ARG: [8] i64 = 0;       # 传给 worker 的 tid（按字节读，故 tid < 128）
var CNT: [8] i64 = 0;       # 每线程弹出个数
var SUM: [8] i64 = 0;       # 每线程弹出的值之和
var SEEN: [4096] i64 = 0;   # 守恒测试的去重表
var PCNT: [8] i64 = 0;      # 每线程实际 push 成功数（调试/判据）
var T0: i64 = 0;
var CFSLOT: i64 = 0;

fn worker(arg: ptr) -> i64 {
    let tid: i64 = 0;
    let i: i64 = 0;
    let s: i64 = 0;
    let v: i64 = 0;
    tid = arg[0];
    i = 0;
    while i < OPS {
        if MODE == 0 {
            if lf_spush(tid, tid * OPS + i + 1) >= 0 {
            PCNT[tid] = PCNT[tid] + 1;
        }
            s = lf_spop(tid);
            if s >= 0 {
                CNT[tid] = CNT[tid] + 1;
                SUM[tid] = SUM[tid] + LF_VAL[s];
                lf_retire(tid, s);
            }
        }
        if MODE == 1 {
            lf_mkpush(tid * OPS + i + 1);
            s = lf_mkpop();
            if s >= 0 {
                CNT[tid] = CNT[tid] + 1;
                SUM[tid] = SUM[tid] + MK_VAL[s];
            }
        }
        if MODE == 3 {
            if lf_spush(tid, tid * OPS + i + 1) >= 0 {
                PCNT[tid] = PCNT[tid] + 1;
            }
        }
        if MODE == 2 {
            lf_qpush(tid, tid * OPS + i + 1);
            v = lf_qpop(tid);
            if v >= 0 {
                CNT[tid] = CNT[tid] + 1;
                SUM[tid] = SUM[tid] + v;
            }
        }
        i = i + 1;
    }
    return 0;
}

fn run_bench(mode: i64, nth: i64, ops: i64) -> i64 {
    let i: i64 = 0;
    let t: i64 = 0;
    MODE = mode;
    NTH = nth;
    OPS = ops;
    i = 0;
    while i < nth {
        CNT[i] = 0;
        SUM[i] = 0;
        ARG[i] = i;
        i = i + 1;
    }
    if mode == 1 {
        lf_mkinit();
    } else {
        lf_init();
    }
    T0 = clock_ms();
    i = 0;
    while i < nth {
        if thread_create(&TH + i * 8, &worker, &ARG + i * 8) != 0 {
            print("thread_create fail\n");
            return -1;
        }
        i = i + 1;
    }
    i = 0;
    while i < nth {
        thread_join(TH[i]);
        i = i + 1;
    }
    t = clock_ms() - T0;
    i = 0;
    while i < nth {
        LF_RN[i] = 0;
        i = i + 1;
    }
    return t;
}

# ---- 单线程顺序性 ----
fn t_seq() -> i64 {
    let i: i64 = 0;
    let s: i64 = 0;
    let ok: i64 = 1;
    lf_init();
    i = 1;
    while i <= 50 {
        lf_spush(0, i);
        i = i + 1;
    }
    i = 50;
    while i >= 1 {
        s = lf_spop(0);
        if s < 0 {
            ok = 0;
            return ok;
        }
        if LF_VAL[s] != i {
            ok = 0;
        }
        lf_retire(0, s);
        i = i - 1;
    }
    return ok;
}

# ---- Michael-Scott 队列 FIFO ----
fn t_fifo() -> i64 {
    let i: i64 = 0;
    let s: i64 = 0;
    let ok: i64 = 1;
    lf_init();
    i = 1;
    while i <= 50 {
        lf_qpush(0, i);
        i = i + 1;
    }
    i = 1;
    while i <= 50 {
        s = lf_qpop(0);
        if s != i {
            ok = 0;
        }
        i = i + 1;
    }
    return ok;
}

# ---- 守恒：多线程 push 全量后 drain，不能丢也不能重复 ----
fn t_cons(nth: i64, ops: i64) -> i64 {
    let i: i64 = 0;
    let j: i64 = 0;
    let s: i64 = 0;
    let v: i64 = 0;
    let npush: i64 = 0;
    let npop: i64 = 0;
    let dup: i64 = 0;
    let oob: i64 = 0;
    MODE = 3;
    NTH = nth;
    OPS = ops;
    lf_init();
    i = 0;
    while i < nth {
        CNT[i] = 0;
        PCNT[i] = 0;
        ARG[i] = i;
        i = i + 1;
    }
    i = 0;
    while i < 4096 {
        SEEN[i] = 0;
        i = i + 1;
    }
    i = 0;
    while i < nth {
        if thread_create(&TH + i * 8, &worker, &ARG + i * 8) != 0 {
            return -1;
        }
        i = i + 1;
    }
    i = 0;
    while i < nth {
        thread_join(TH[i]);
        i = i + 1;
    }
    npush = nth * ops;
    # drain
    s = lf_spop(0);
    while s >= 0 {
        v = LF_VAL[s];
        if v < 1 {
            oob = oob + 1;
        }
        if v > npush {
            oob = oob + 1;
        }
        if v >= 1 {
            if v <= npush {
                if SEEN[v] == 1 {
                    dup = dup + 1;
                }
                SEEN[v] = 1;
            }
        }
        npop = npop + 1;
        lf_retire(0, s);
        if npop > npush + 16 {
            print("drain runaway\n");
            return -1;
        }
        s = lf_spop(0);
    }
    j = 0;
    i = 1;
    while i <= npush {
        if SEEN[i] == 0 {
            j = j + 1;
        }
        i = i + 1;
    }
    print("cons npush=");
    print_i64(npush);
    print(" drained=");
    print_i64(npop);
    print(" pushed=");
    print_i64(PCNT[0] + PCNT[1] + PCNT[2] + PCNT[3]);
    print(" npop=");
    print_i64(npop);
    print(" missing=");
    print_i64(j);
    print(" dup=");
    print_i64(dup);
    print(" oob=");
    print_i64(oob);
    print_nl();
    if npop == npush {
        if j == 0 {
            if dup == 0 {
                if oob == 0 {
                    return 1;
                }
            }
        }
    }
    return 0;
}

# ---- ABA：受控交错（不保护 + 复用同一槽位）----
#   教科书场景：读 head=A、next=B；别人 pop A、pop B、再把 A 推回来；
#   然后把 B 当 head 写回去 —— B 早已不在栈里，A 丢失。
fn t_aba(notag: i64) -> i64 {
    let s: i64 = 0;
    let ok: i64 = 0;
    let n: i64 = 0;
    LF_NOTAG = notag;
    lf_init();
    lf_spush(0, 1);
    lf_spush(0, 2);
    lf_spush(0, 3);
    s = lf_pop_begin();          # 记下 head=slot(3)、next=slot(2)
    # 干扰窗口
    lf_spop_raw();               # pop 掉 slot(3)
    lf_retire(0, s);
    lf_flush(0);                 # 没有危险指针 → 真的被回收
    lf_spush(0, 3);              # 分配到的正是同一个槽位
    ok = lf_pop_commit();        # 有 tag → 失败(0)；无 tag → 成功(1)
    LF_NOTAG = 0;
    # 数一数栈里还剩几个
    n = 0;
    s = lf_spop(0);
    while s >= 0 {
        n = n + 1;
        lf_retire(0, s);
        s = lf_spop(0);
    }
    print("aba notag=");
    print_i64(notag);
    print(" commit=");
    print_i64(ok);
    print(" left=");
    print_i64(n);
    print_nl();
    return n;
}

# ---- UAF：pop 出来的槽位在还被引用时被回收复用 ----
fn t_uaf(protect: i64) -> i64 {
    let s: i64 = 0;
    let v: i64 = 0;
    lf_init();
    lf_spush(0, 1);
    lf_spush(0, 2);
    lf_spush(0, 3);
    if protect == 1 {
        s = lf_pop_beginP(0);
    } else {
        s = lf_pop_begin();
    }
    lf_spop_raw();               # 别人把 head pop 掉
    lf_retire(0, s);
    lf_flush(0);                 # protect=1 时这一步回收不掉
    lf_spush(0, 999);            # 立刻复用槽位并覆盖
    v = LF_VAL[s];               # protect=0 → 读到 999（UAF）
    if protect == 1 {
        lf_unprotectP(0);
    }
    print("uaf protect=");
    print_i64(protect);
    print(" val=");
    print_i64(v);
    print_nl();
    return v;
}


# 🔴 确定性场景：必然失败的 CAS
#
# M1（去掉 & 255）之所以难抓，是因为它只在"EAX 高 24 位有垃圾"时才发作，
# 并发测试撞不撞得上取决于调度时序 —— 实测 M1 下 15 项断言仍全绿。
# 这里改成**单线程 + 必然不匹配**，并在调用前用 clock_ms() 把 EAX 弄脏，
# 让那条因果链每次都必然走到。
#
# 判据三条，缺一不可：
#   r == 0       失败必须报失败（M1 下为 1）
#   c == 100000  失败不得改写目标（M1 下 CAS 语义本身仍正确，靠它区分）
#   e == 100000  失败必须把实际值写回（M1 下同样正确，故 r 才是主键）
fn t_casfail() -> i64 {
    let r: i64 = 0;

    let i: i64 = 0;
    let rs: i64 = 0;
    CFSLOT = 100000;
    i = 0;
    rs = 0;
    while i < 200 {
        # 让 RAX/EAX 带上一个大数的残余：调用本身的返回值就在 RAX，
        # 原先还多存一份到 junk 却从没人读（tools/unused.py 报出来的）。
        clock_ms();
        r = lf_cas(0, &CFSLOT, 999, 7);
        rs = rs + r;
        i = i + 1;
    }
    print("casfail rsum=");
    print_i64(rs);
    print(" c=");
    print_i64(CFSLOT);
    print(" e=");
    print_i64(LF_EXP[0]);
    print_nl();
    return rs;
}

fn main() -> i64 {
    let nth: i64 = 4;
    let ops: i64 = 1000;
    let a: i64 = 0;
    let b: i64 = 0;
    let c: i64 = 0;
    let t1: i64 = 0;
    let t2: i64 = 0;
    let t3: i64 = 0;
    let ok: i64 = 0;

    ok = t_seq();
    print("seq ok=");
    print_i64(ok);
    print_nl();

    ok = t_fifo();
    print("fifo ok=");
    print_i64(ok);
    print_nl();

    ok = t_cons(nth, ops);
    print("cons ok=");
    print_i64(ok);
    print_nl();

    b = t_casfail();             # 必然失败的 CAS：必须返回 0
    print("casfail_r=");
    print_i64(b);
    print_nl();

    a = t_aba(0);                # 有 tag：应剩 3
    b = t_aba(1);                # 无 tag：应剩 2（ABA 丢了一个）
    c = t_uaf(0);                # 不保护：应读到 999
    # 这三个期望值原先只写在注释里，b/c 赋完就没人再读 —— 等于没验。
    print("aba_notag=");
    print_i64(b);
    print(" uaf_unprot=");
    print_i64(c);
    print_nl();
    a = t_uaf(1);                # 保护：应仍是 3
    print("uaf_prot=");
    print_i64(a);
    print_nl();

    t1 = run_bench(0, nth, 20000);
    print("bench lf_ms=");
    print_i64(t1);
    print(" casfail=");
    print_i64(LF_CASFAIL);
    print(" dual=");
    print_i64(LF_DUAL);
    print_nl();
    t2 = run_bench(1, nth, 20000);
    print("bench mt_ms=");
    print_i64(t2);
    print_nl();
    t3 = run_bench(2, nth, 20000);
    print("bench q_ms=");
    print_i64(t3);
    print(" casfail=");
    print_i64(LF_CASFAIL);
    print(" dual=");
    print_i64(LF_DUAL);
    print_nl();
    return 0;
}
