# bench —— 性能基准（性能基线）
#
#   ./bench                 人类可读报告
#   ./bench --csv           机器可读（供 tools/benchtest.sh 对比基线）
#
# 为什么写它：上一轮实测发现「寄存器分配会**增大**体积而不是减小」，
# 于是"真 IR"的价值主张变成**性能**。但本项目此前没有任何性能基线 ——
# 改了代码生成也不知道是快了还是慢了。
#
# 这组 workload 刻意以**表达式计算**为主（push/pop 密集），因为那正是
# 寄存器分配会影响的部分。若哪天真做了寄存器分配，这里的数字就是判据。
#
# 计时用 clock_gettime 系统调用（228），不依赖 libc。
import "io.mo";

var TS: [2] i64 = 0;

fn now_ns() -> i64 {
    let r: i64 = syscall(228, 1, &TS, 0, 0, 0, 0);
    return TS[0] * 1000000000 + TS[1];
}

var ACC: i64 = 0;      # 防止优化掉：结果必须被"用到"

# ---- 1. 整数算术：表达式求值密集（push/pop 最密集的场景）----
fn w_arith(n: i64) -> i64 {
    let i: i64 = 0;
    let s: i64 = 0;
    while i < n {
        s = s + i * 3 - (i / 2) + (i % 7) * 2;
        i = i + 1;
    }
    return s;
}

# ---- 2. 函数调用：调用约定与参数传递开销 ----
fn leaf3(a: i64, b: i64, c: i64) -> i64 {
    return a * 2 + b * 3 - c;
}
fn w_call(n: i64) -> i64 {
    let i: i64 = 0;
    let s: i64 = 0;
    while i < n {
        s = s + leaf3(i, i + 1, i + 2);
        i = i + 1;
    }
    return s;
}

# ---- 3. 递归：栈帧建立/销毁 ----
fn fib(n: i64) -> i64 {
    if n < 2 { return n; }
    return fib(n - 1) + fib(n - 2);
}
fn w_recur(n: i64) -> i64 {
    let i: i64 = 0;
    let s: i64 = 0;
    while i < n {
        s = s + fib(14);
        i = i + 1;
    }
    return s;
}

# ---- 4. 数组访问：内存读写（受寄存器分配影响较小，作对照）----
var ARR: [256] i64 = 0;
fn w_array(n: i64) -> i64 {
    let i: i64 = 0;
    while i < 256 { ARR[i] = i * 5; i = i + 1; }
    let s: i64 = 0;
    let k: i64 = 0;
    while k < n {
        let j: i64 = 0;
        while j < 256 { s = s + ARR[j]; j = j + 1; }
        k = k + 1;
    }
    return s;
}

# ---- 5. 局部变量读写：栈槽访问 ----
fn w_local(n: i64) -> i64 {
    let a: i64 = 1;
    let b: i64 = 2;
    let c: i64 = 3;
    let i: i64 = 0;
    while i < n {
        a = a + b;
        b = b + c;
        c = c + a;
        if a > 1000000 { a = 1; }
        if b > 1000000 { b = 2; }
        if c > 1000000 { c = 3; }
        i = i + 1;
    }
    return a + b + c;
}

fn run(name: ptr, f: i64, n: i64) -> i64 {
    let t0: i64 = now_ns();
    let v: i64 = 0;
    if f == 1 { v = w_arith(n); }
    if f == 2 { v = w_call(n); }
    if f == 3 { v = w_recur(n); }
    if f == 4 { v = w_array(n); }
    if f == 5 { v = w_local(n); }
    let t1: i64 = now_ns();
    ACC = ACC + v;
    print(name);
    print("  ");
    print_i64(t1 - t0);
    print(" ns");
    print("\n");
    return t1 - t0;
}

fn main() -> i64 {
    # 迭代次数：让每个 workload 落在 10ms ~ 500ms，保证可测量
    run("arith   ", 1, 3000000);
    run("call    ", 2, 2000000);
    run("recur   ", 3, 200);
    run("array   ", 4, 20000);
    run("local   ", 5, 3000000);
    print("checksum ");
    print_i64(ACC % 1000000);
    print("\n");
    return 0;
}
