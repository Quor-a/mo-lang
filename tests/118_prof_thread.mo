# 118 —— prof.mo 与 thread.mo 的测试覆盖（1.92 / 1.93 修正）
# expect: 0
#
# 这两个库此前没有任何 tests/*.mo 引用（projcheck 第 3 项一直是红灯）。
# 补的时候不能"import 了就算覆盖"——必须有真实断言。
#
# 🔴 为什么不断言「3 线程加锁自增 = 3000」：
#    thread.mo 的 pthread_* 是 extern，必须 molink 链上 libc 才有地址。
#    而 tests/run.sh 用的是**裸 moc**（不链任何库），pthread_create 的地址
#    是 0，调用不报错、也不创建线程 —— CNT 恒为 0。
#    第一版就是这样，表现是断言失败而非崩溃，很容易误判成"锁没生效"。
#    真正的多线程断言在 tools/threadtest.sh（那条走 molink + libc）。
#
# 所以这里只断言 thread.mo 里**不依赖 libc** 的两条：
#   usleep（纯 nanosleep 系统调用）
#   futex（纯 futex 系统调用）
# 两者在裸 moc 下都能真跑，断言是真的在起作用。
import "assert.mo";
import "prof.mo";
import "thread.mo";
import "io.mo";

var M: [8] i64 = 0;
var TSV: [2] i64 = 0;

fn now_ns() -> i64 {
    syscall(228, 1, &TSV, 0, 0, 0, 0);
    return TSV[0] * 1000000000 + TSV[1];
}

fn main() -> i64 {
    # ---- prof：调用计数必须真的记到 ----
    prof_enter("a");
    prof_leave();
    prof_enter("a");
    prof_leave();
    assert_eq("prof 调用计数", P_CNT[0], 2);

    # ---- futex：*p != val 时立刻返回 -EAGAIN，不会挂住 ----
    M[0] = 7;
    let r: i64 = futex_wait(&M, 3);
    assert_true("futex 值不匹配返回负 errno", r < 0);
    assert_eq("futex 返回 -EAGAIN", r, 0 - 11);

    # ---- usleep：睡 20ms，实测流逝必须 >= 10ms ----
    let t0: i64 = now_ns();
    usleep(20000);
    let t1: i64 = now_ns();
    let d: i64 = t1 - t0;
    assert_true("usleep(20000) 至少睡满 10ms", d >= 10000000);

    return test_done();
}
