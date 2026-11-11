# prof.mo —— 确定性（插桩式）性能分析器
import "io.mo";
import "str.mo";

# 用法一（自动）：moc prog.mo -p prog.elf
#   编译器自动在每个函数入口插 prof_enter("函数名")、出口插 prof_leave()，
#   main 的出口额外插 prof_report()。只对**主文件**的函数插桩 ——
#   库函数（strlen/print）被调用几百万次，插上去既污染数据又拖慢到不可信。
#
# 用法二（手工）：在关心的区间前后写 prof_enter("名字") / prof_leave()，
#   结束时调 prof_report()。
#
# 计时用 clock_gettime 系统调用（228），**不依赖 libc**，
# 所以 -p 程序生成的是普通 ELF，不需要走 molink。

var P_NAMES: [64] i64 = 0;
var P_CNT:   [64] i64 = 0;
# 累计耗时（含子调用）
var P_TOT:   [64] i64 = 0;
# 累计的**子调用**耗时
var P_CHILD: [64] i64 = 0;
# 自身耗时 = 累计 - 子调用
var P_SELF:  [64] i64 = 0;
# 调用栈：函数 id
var P_STK:   [64] i64 = 0;
# 调用栈：进入时刻（ns）
var P_STKT:  [64] i64 = 0;
# 调用栈：**本次调用**已计入子调用的时间（每帧独立，不能共用全局）
var P_STKC:  [64] i64 = 0;
var P_NFN:   i64 = 0;
var P_SP:    i64 = 0;
# timespec
var P_TS:    [2] i64 = 0;

# 单调时钟纳秒
#
# 🔴 参数顺序：`int clock_gettime(clockid_t clockid, struct timespec *tp)`
#    即 rdi=clockid、rsi=缓冲。第一版写成 syscall(228, &P_TS, 1, ...)，
#    把缓冲当 clockid、把 1 当地址 —— 调用返回 -EFAULT，时刻恒为 0，
#    于是**所有耗时都显示 0 ms**，看起来像"程序跑得太快"。
#    没有任何报错，是这类 bug 最难发现的地方。
fn prof_now() -> i64 {
    syscall(228, 1, &P_TS, 0, 0, 0, 0);
    return P_TS[0] * 1000000000 + P_TS[1];
}

fn prof_id(name: i64) -> i64 {
    let i: i64 = 0;
    while i < P_NFN {
        if strcmp(P_NAMES[i], name) == 0 { return i; }
        i = i + 1;
    }
    if P_NFN < 64 {
        P_NAMES[P_NFN] = name;
        let id: i64 = P_NFN;
        P_NFN = P_NFN + 1;
        return id;
    }
    return 63;
}

fn prof_enter(name: i64) -> i64 {
    let id: i64 = prof_id(name);
    P_CNT[id] = P_CNT[id] + 1;
    if P_SP < 64 {
        P_STK[P_SP] = id;
        P_STKT[P_SP] = prof_now();
        P_STKC[P_SP] = 0;
        P_SP = P_SP + 1;
    }
    return 0;
}

fn prof_leave() -> i64 {
    if P_SP <= 0 { return 0; }
    P_SP = P_SP - 1;
    let id: i64 = P_STK[P_SP];
    let d: i64 = prof_now() - P_STKT[P_SP];
    P_TOT[id] = P_TOT[id] + d;
    # 这段时间同时是**调用者**的子调用开销。
    #
    # 🔴 不能用一个「每次 enter 就清零」的全局 P_CHILD[id]：
    #    同一函数被调 20 次时，只有最后一次的子调用时间被留下，
    #    自身耗时被严重高估。必须每个栈帧各记一份（P_STKC），
    #    leave 时累加到调用者的那一帧上。
    if P_SP > 0 { P_STKC[P_SP - 1] = P_STKC[P_SP - 1] + d; }
    P_CHILD[id] = P_CHILD[id] + P_STKC[P_SP];
    P_SELF[id] = P_TOT[id] - P_CHILD[id];
    return 0;
}

# 毫秒（保留一位小数：ms10 = ns / 100000）
fn prof_report() -> i64 {
    print("\n=== profiler ===\n");
    print("函数                 调用次数      累计(ms)     自身(ms)\n");
    let i: i64 = 0;
    while i < P_NFN {
        print(P_NAMES[i]);
        let pad: i64 = 20 - strlen(P_NAMES[i]);
        while pad > 0 { print(" "); pad = pad - 1; }
        print_i64(P_CNT[i]);
        print("        ");
        # 一位小数的毫秒：整数部分 + "." + 小数位
        print_i64(P_TOT[i] / 1000000);
        print(".");
        print_i64((P_TOT[i] / 100000) % 10);
        print("        ");
        print_i64(P_SELF[i] / 1000000);
        print(".");
        print_i64((P_SELF[i] / 100000) % 10);
        print("\n");
        i = i + 1;
    }
    return 0;
}
