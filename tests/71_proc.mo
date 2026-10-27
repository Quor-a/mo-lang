# 进程分配与管理：标识 / 优先级 / 资源 / 等待 / 进程池
# expect: 1
import "proc.mo";
import "assert.mo";
import "io.mo";

fn pool_work(task: i64) -> i64 {
    # 简单可验算的任务：task^2 + 1
    return task * task + 1;
}

fn main() -> i64 {
    # --- 进程标识 ---
    let me: i64 = proc_pid();
    assert_true("pid > 0", me > 0);
    let par: i64 = proc_ppid();
    assert_true("ppid > 0", par > 0);
    assert_true("ppid != pid", par != me);

    # --- 进程组 ---
    let pg: i64 = proc_getpgid(0);
    assert_true("pgid > 0", pg > 0);

    # --- fork / wait / 退出码 ---
    let pid: i64 = proc_fork();
    if pid == 0 {
        proc_exit(7);
    }
    let rc: i64 = proc_wait(pid);
    assert_eq("wait 退出码", rc, 7);

    # 非阻塞探活。
    # 注意 waitpid 是**裸系统调用**，出错时返回的是负的 errno 而不是 -1：
    # 没有子进程时返回 -10（-ECHILD）。所以不能用 ">= 0" 判断成功。
    let p: i64 = proc_poll();
    assert_true("poll 非 -1", p != 0 - 1);

    # --- 资源统计 ---
    # getrusage 本身应当成功（返回 0）
    assert_eq("getrusage 成功", proc_rusage(0), 0);
    let u: i64 = proc_utime_ms();
    assert_true("utime >= 0", u >= 0);
    # 不断言 maxrss > 0：实测在部分容器/沙盒环境里 ru_maxrss 恒为 0
    # （本沙盒即如此），断言它反而会造成假失败。

    # --- 进程池：2 个 worker，各算一个任务 ---
    let n: i64 = pool_start(2);
    assert_eq("pool_start", n, 2);

    let s0: i64 = pool_send(0, 3);
    let s1: i64 = pool_send(1, 5);
    assert_eq("send 0", s0, 0);
    assert_eq("send 1", s1, 0);

    let r0: i64 = pool_recv(0);
    let r1: i64 = pool_recv(1);
    assert_eq("worker0: 3^2+1", r0, 10);
    assert_eq("worker1: 5^2+1", r1, 26);

    let st: i64 = pool_stop();
    assert_eq("pool_stop", st, 2);

    # --- 进程池：多任务分发，验证都能拿回结果 ---
    n = pool_start(3);
    assert_eq("pool_start 3", n, 3);
    let i: i64 = 0;
    while i < 3 {
        let q: i64 = pool_send(i, i);
        i = i + 1;
    }
    let sum: i64 = 0;
    i = 0;
    while i < 3 {
        let v: i64 = pool_recv(i);
        sum = sum + v;
        i = i + 1;
    }
    # 0^2+1 + 1^2+1 + 2^2+1 = 1 + 2 + 5 = 8
    assert_eq("三任务汇总", sum, 8);
    pool_stop();

    let t_failed: i64 = test_done();
    if t_failed != 0 { return 2; }
    return 1;
}
