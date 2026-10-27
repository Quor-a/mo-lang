# supertree.mo —— Actor 模型 + 监督树：端到端实测
#
# 判据不是"有没有崩"，而是**三个策略必须给出三个不同的重启集合**：
#   one-for-one   : 只重启失败者      → gen=[0,1,0]  msgn=[60,0,60]
#   one-for-all   : 重启全部          → gen=[1,1,1]  msgn=[0,0,0]
#   rest-for-one  : 失败者及其之后    → gen=[0,1,1]  msgn=[60,0,0]
# msgn 在重启时归零，未重启的保留 —— 这正是"重启 = 重建"的可观测后果。
#
# 另一条独立判据是**重启强度**：窗口内重启超限 → 监督者自己崩，
# 绝不静默无限重启（那会把崩溃循环伪装成"一直在工作"）。

import "io.mo";
import "thread.mo";
import "csp.mo";
import "actor.mo";

var CRASHV: i64 = 999;        # 让 worker 崩溃的消息
var SWITCHV: i64 = 500;       # 让 worker 切换行为的消息

# 普通 worker：每条消息 +1
fn worker() -> i64 {
    let m: i64 = 0;
    while 1 {
        m = act_recv();
        if m == ACT_STOPV { return act_leave(0); }
        if m == CRASHV { return act_crash(7); }
        act_bump(1);
    }
    return act_leave(0);
}

# 会 become 的 worker：行为 0 每条 +1，行为 1 每条 +10
fn worker_b() -> i64 {
    let m: i64 = 0;
    while 1 {
        m = act_recv();
        if m == ACT_STOPV { return act_leave(0); }
        if m == SWITCHV {
            act_become(1);
        } else {
            if act_beh() == 0 { act_bump(1); } else { act_bump(10); }
        }
    }
    return act_leave(0);
}

# 🔴 每个场景必须用**全新的一套** worker 线程，而且旧的那套要先回收掉。
#    lib/csp.mo 的 csp_loop 在 `CSP_FIN >= CSP_NC` 时会自行 return ——
#    即"这一轮协程都跑完了，调度器线程就该退出"。于是：
#      · 只 init 一次  → A 跑完后 4 个 worker 全部退出，B 的协程**永远
#        不被调度**：不报错、不崩溃，msgn 恒为 0、gen 恒为 0。
#      · 每场景 init 但不回收 → 新旧两套线程都用 w=0..3，抢同一条队列。
#    正确顺序是：场景结束 → csp_sched()（等 FIN 追平并 pthread_join 回收）
#    → 下一场景重置计数 → csp_init() 起新线程。任何时刻只有一套调度器。
fn csp_reinit(nw: i64) -> i64 {
    CSP_NC = 0;
    CSP_FIN = 0;
    CSP_STOP = 0;
    CSP_DEAD = 0;
    return csp_init(nw);
}

fn scene_end(sup: i64) -> i64 {
    sup_stop(sup);
    act_join(20000);
    return csp_sched();
}

# A. 状态私有 + 消息无丢失：三个 actor 各收 100 条
fn scene_isolate() -> i64 {
    csp_reinit(4);
    let sup: i64 = sup_new(STRAT_ONE, 3, 1000);
    let p0: i64 = sup_addch(sup, &worker, 0);
    let p1: i64 = sup_addch(sup, &worker, 0);
    let p2: i64 = sup_addch(sup, &worker, 0);
    sup_start(sup);
    let i: i64 = 0;
    while i < 100 {
        act_send(p0, 1);
        act_send(p1, 1);
        act_send(p2, 1);
        i = i + 1;
    }
    act_waitmsgn(p0, 100, 40000);
    act_waitmsgn(p1, 100, 40000);
    act_waitmsgn(p2, 100, 40000);
    print("a_m0="); print_i64(ACT_MSGN[p0]); print("\n");
    print("a_m1="); print_i64(ACT_MSGN[p1]); print("\n");
    print("a_m2="); print_i64(ACT_MSGN[p2]); print("\n");
    print("a_s0="); print_i64(ACT_ST[p0]); print("\n");
    scene_end(sup);
    return 0;
}

# 等到"该重启的都重启了、不该重启的没重启"
fn act_waitset(sup: i64, tgt: i64, cap: i64) -> i64 {
    let st: i64 = ACT_SS[sup];
    let n: i64 = ACT_SN[sup];
    let pt: i64 = sup_child(sup, tgt);
    let pl: i64 = sup_child(sup, n - 1);
    let ph: i64 = sup_child(sup, 0);
    let spin: i64 = 0;
    let ok: i64 = 0;
    while spin < cap {
        ok = 1;
        if ACT_GEN[pt] < 1 { ok = 0; }
        if st == STRAT_ALL { if ACT_GEN[ph] < 1 { ok = 0; } }
        if st == STRAT_REST { if ACT_GEN[pl] < 1 { ok = 0; } }
        # 反向守卫：one-for-one 下头一个**不该**被重启；真被重启了就永远等不到
        if st == STRAT_ONE { if ACT_GEN[ph] > 0 { ok = 0; } }
        if sup_allalive(sup) == 0 { ok = 0; }
        if ok == 1 { return 0; }
        usleep(500);
        spin = spin + 1;
    }
    return 0 - 1;
}

# B/C/D. 三个重启策略
fn scene_strat(strat: i64, tgt: i64, tagn: ptr) -> i64 {
    csp_reinit(4);
    let sup: i64 = sup_new(strat, 5, 1000);
    let p0: i64 = sup_addch(sup, &worker, 0);
    let p1: i64 = sup_addch(sup, &worker, 0);
    let p2: i64 = sup_addch(sup, &worker, 0);
    sup_start(sup);
    let i: i64 = 0;
    while i < 60 {
        act_send(p0, 1);
        act_send(p1, 1);
        act_send(p2, 1);
        i = i + 1;
    }
    act_waitmsgn(p2, 60, 40000);
    act_send(sup_child(sup, tgt), CRASHV);
    act_waitset(sup, tgt, 40000);
    print(tagn); print("_diag="); print_i64(ACT_DIAG[0]); print(",");
    print_i64(ACT_DIAG[1]); print(","); print_i64(ACT_DIAG[2]); print(",");
    print_i64(ACT_DIAG[3]); print(","); print_i64(ACT_DIAG[4]); print(",");
    print_i64(ACT_DIAG[5]); print("\n");
    print(tagn); print("_g0="); print_i64(ACT_GEN[p0]); print("\n");
    print(tagn); print("_g1="); print_i64(ACT_GEN[p1]); print("\n");
    print(tagn); print("_g2="); print_i64(ACT_GEN[p2]); print("\n");
    print(tagn); print("_m0="); print_i64(ACT_MSGN[p0]); print("\n");
    print(tagn); print("_m1="); print_i64(ACT_MSGN[p1]); print("\n");
    print(tagn); print("_m2="); print_i64(ACT_MSGN[p2]); print("\n");
    scene_end(sup);
    return 0;
}

# E. 重启强度：intensity=2, period=1000ms，连崩 3 次 → 第 3 次监督者自己崩
fn scene_inten() -> i64 {
    csp_reinit(4);
    let sup: i64 = sup_new(STRAT_ONE, 2, 1000);
    let p0: i64 = sup_addch(sup, &worker, 0);
    sup_start(sup);
    let i: i64 = 0;
    while i < 3 {
        act_send(p0, CRASHV);
        let spin: i64 = 0;
        while spin < 40000 {
            if ACT_GEN[p0] > i { break; }
            if ACT_SFAIL[sup] != 0 { break; }
            usleep(500);
            spin = spin + 1;
        }
        i = i + 1;
    }
    print("e_gen="); print_i64(ACT_GEN[p0]); print("\n");
    print("e_sfail="); print_i64(ACT_SFAIL[sup]); print("\n");
    print("e_state="); print_i64(ACT_STATE[p0]); print("\n");
    scene_end(sup);
    return 0;
}

# E2. 对照：窗口过期 → 计数重置 → 不超限
fn scene_inten2() -> i64 {
    csp_reinit(4);
    let sup: i64 = sup_new(STRAT_ONE, 1, 150);
    let p0: i64 = sup_addch(sup, &worker, 0);
    sup_start(sup);
    let i: i64 = 0;
    while i < 2 {
        act_send(p0, CRASHV);
        let spin: i64 = 0;
        while spin < 40000 {
            if ACT_GEN[p0] > i { break; }
            if ACT_SFAIL[sup] != 0 { break; }
            usleep(500);
            spin = spin + 1;
        }
        usleep(300000);          # 300ms > period 150ms → 窗口过期
        i = i + 1;
    }
    print("e2_gen="); print_i64(ACT_GEN[p0]); print("\n");
    print("e2_sfail="); print_i64(ACT_SFAIL[sup]); print("\n");
    scene_end(sup);
    return 0;
}

# F. become：行为切换前后对同一消息的处理不同
fn scene_become() -> i64 {
    csp_reinit(4);
    let sup: i64 = sup_new(STRAT_ONE, 3, 1000);
    let p0: i64 = sup_addch(sup, &worker_b, 0);
    sup_start(sup);
    let i: i64 = 0;
    while i < 3 { act_send(p0, 1); i = i + 1; }
    act_waitmsgn(p0, 3, 40000);
    print("f_pre="); print_i64(ACT_ST[p0]); print("\n");
    act_send(p0, SWITCHV);
    let spin: i64 = 0;
    while spin < 40000 {
        if ACT_BEH[p0] == 1 { break; }
        usleep(500);
        spin = spin + 1;
    }
    i = 0;
    while i < 2 { act_send(p0, 1); i = i + 1; }
    act_waitmsgn(p0, 5, 40000);
    print("f_post="); print_i64(ACT_ST[p0]); print("\n");
    print("f_beh="); print_i64(ACT_BEH[p0]); print("\n");
    scene_end(sup);
    return 0;
}

fn main() -> i64 {
    act_reset();

    print("=== A. 状态私有 + 消息无丢失 ===\n");
    scene_isolate();

    print("=== B. one-for-one ===\n");
    scene_strat(STRAT_ONE, 1, "b");
    print("=== C. one-for-all ===\n");
    scene_strat(STRAT_ALL, 1, "c");
    print("=== D. rest-for-one ===\n");
    scene_strat(STRAT_REST, 1, "d");

    print("=== E. 重启强度（窗口内）===\n");
    scene_inten();
    print("=== E2. 窗口过期 → 计数重置 ===\n");
    scene_inten2();

    print("=== F. become ===\n");
    scene_become();

    print("=== 诊断 ===\n");
    print("dup="); print_i64(ACT_DUP); print("\n");
    print("nrs="); print_i64(ACT_NRS); print("\n");
    print("sfailn="); print_i64(ACT_SFAILN); print("\n");
    print("noch="); print_i64(ACT_NOCH); print("\n");
    print("senderr="); print_i64(ACT_SENDERR); print("\n");
    print("hang="); print_i64(ACT_HANG); print("\n");
    print("diag_st="); print_i64(ACT_DIAG[0]); print("\n");
    print("diag_idx="); print_i64(ACT_DIAG[1]); print("\n");
    print("diag_lo="); print_i64(ACT_DIAG[2]); print("\n");
    print("diag_hi="); print_i64(ACT_DIAG[3]); print("\n");
    print("diag_cpid="); print_i64(ACT_DIAG[4]); print("\n");
    print("diag_sn="); print_i64(ACT_DIAG[5]); print("\n");
    print("live="); print_i64(ACT_LIVE); print("\n");
    print("dead="); print_i64(CSP_DEAD); print("\n");
    return 0;
}
