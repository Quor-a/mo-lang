# timersel.mo —— select 的超时：把定时器做成"一个普通的 channel"
#
# Go 里超时不是一个语言特性，而是：
#       select {
#       case j := <-jobs:
#       case <-time.After(500 * time.Millisecond):
#       }
# 本例在墨语言里做同一件事 —— 且同样不需要给 select 加任何新语法。
#
# 运行（必须 molink + libc）：
#   ../bin/moc timersel.mo -c timersel.o && bash ../tools/molink.sh timersel.o -o timersel
#   ./timersel

import "io.mo";
import "cstd.mo";
import "thread.mo";
import "csp.mo";
import "select.mo";
import "timer.mo";

var JOBS: i64 = 0;
var DONE: i64 = 0;
var TO: i64 = 0;
var AIM: [5] i64 = 0;
var EL: [5] i64 = 0;
var HIT: [5] i64 = 0;
var N: i64 = 5;

# 每轮给 400ms：有活就干活，没活就超时记一笔
fn worker() -> i64 {
    let i: i64 = 0;
    let t: i64 = 0;
    let k: i64 = 0;
    let a: i64 = 0;
    let b: i64 = 0;
    while i < N {
        t = tm_after(400);
        a = clock_ms();
        sel_reset();
        sel_case(JOBS, 1, 0);
        sel_case(t, 1, 0);
        k = sel_go(0);
        b = clock_ms();
        EL[i] = b - a;
        HIT[i] = k;
        if k == 0 { DONE = DONE + 1; } else { TO = TO + 1; }
        i = i + 1;
    }
    csp_exit();
    return 0;
}

# 只投 2 个活，之后就再也不投 —— 后面 3 轮必须超时
fn feeder() -> i64 {
    chan_send(JOBS, 101);
    chan_send(JOBS, 102);
    csp_exit();
    return 0;
}

fn main() -> i64 {
    let i: i64 = 0;
    if csp_init(1) != 0 { print("csp_init fail\n"); return 1; }
    sel_init();
    if tm_init(16) != 0 { print("tm_init fail\n"); return 1; }
    JOBS = chan_make(8);
    csp_go(&worker, 0);
    csp_go(&feeder, 0);
    if csp_sched() != 0 { print("sched fail\n"); return 1; }
    tm_stop();

    print("轮次  命中      耗时ms  说明\n");
    i = 0;
    while i < N {
        print("  ");   print_i64(i);
        print("   ");  print_i64(HIT[i]);
        print("      "); print_i64(EL[i]);
        print("   ");
        if HIT[i] == 0 { print("收到活\n"); } else { print("超时\n"); }
        i = i + 1;
    }
    print("干活 "); print_i64(DONE); print(" 次，超时 "); print_i64(TO); print(" 次\n");
    print("tick 精度 = "); print_i64(TM_TICK); print(" ms（误差上界）\n");
    return 0;
}
