# parallel.mo —— 用进程池并行筛素数（真实的多进程程序）
#
#   ./bin/moc examples/parallel.mo /tmp/par.elf && /tmp/par.elf
#
# 做法：把 [1, N] 切成 W 段，每段交给一个 worker 进程去数素数，
# 父进程汇总。最后与**单进程串行结果**比对，必须一致。
#
# 这是"进程分配"最经典的验证：并行结果必须等于串行结果，
# 而不仅仅是"看起来跑起来了"。
import "proc.mo";
import "io.mo";
import "str.mo";

var N: i64 = 200000;      # 统计范围
var W: i64 = 4;           # worker 数量
var SEG: i64 = 0;         # 每段的宽度

# ---- 约定的 pool_work：统计一段里的素数个数 ----
# task 是段号，负责 [task*SEG+1, (task+1)*SEG]
fn is_prime(n: i64) -> i64 {
    if n < 2 { return 0; }
    if n == 2 { return 1; }
    if (n - (n / 2) * 2) == 0 { return 0; }
    let d: i64 = 3;
    while d * d <= n {
        if n - (n / d) * d == 0 { return 0; }
        d = d + 2;
    }
    return 1;
}

fn pool_work(task: i64) -> i64 {
    let lo: i64 = task * SEG + 1;
    let hi: i64 = lo + SEG - 1;
    if hi > N { hi = N; }
    let c: i64 = 0;
    let i: i64 = lo;
    while i <= hi {
        if is_prime(i) == 1 { c = c + 1; }
        i = i + 1;
    }
    return c;
}

fn main() -> i64 {
    SEG = (N + W - 1) / W;

    print("parallel prime counting with a process pool\n");
    print("range = 1..");
    print_i64(N);
    print("   workers = ");
    print_i64(W);
    print_nl();

    let n: i64 = pool_start(W);
    if n != W {
        print("pool_start failed\n");
        return 1;
    }
    print("forked ");
    print_i64(W);
    print(" worker processes\n");

    # 分配任务：第 i 段给第 i 个 worker
    let i: i64 = 0;
    while i < W {
        let r: i64 = pool_send(i, i);
        i = i + 1;
    }

    # 收集结果
    let total: i64 = 0;
    i = 0;
    while i < W {
        let got: i64 = pool_recv(i);
        if got < 0 { print("recv failed\n"); return 1; }
        print("  worker ");
        print_i64(i);
        print(" (pid ");
        print_i64(P_PID[i]);
        print(") found ");
        print_i64(got);
        print_nl();
        total = total + got;
        i = i + 1;
    }

    let k: i64 = pool_stop();
    print("parallel total = ");
    print_i64(total);
    print_nl();

    # ---- 串行复算，必须一致 ----
    let s: i64 = 0;
    let j: i64 = 1;
    while j <= N {
        if is_prime(j) == 1 { s = s + 1; }
        j = j + 1;
    }
    print("serial   total = ");
    print_i64(s);
    print_nl();

    if total == s {
        print("MATCH: parallel == serial\n");
        return 0;
    }
    print("MISMATCH\n");
    return 1;
}
