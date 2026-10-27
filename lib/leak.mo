# leak —— 分配追踪与泄漏报告
#
# **解决什么问题**：malloc/free 漏掉一个 free 是**静默错误** ——
# 不报错、不崩溃、结果也对，只是内存一路涨。等到 OOM 时，
# 离真正的出错点已经有十万八千里。
#
# 这个库包装 malloc/free，记录每一笔**尚未释放**的分配，
# 程序结束时报告还剩多少、共多少字节。
#
# 用法：
#   leak_init();
#   ... 正常写代码，但用 lmalloc / lfree 代替 malloc / free ...
#   leak_report();        # 打印未释放的
#
# 也可以只在**怀疑有泄漏的模块**里用，其余照旧。

import "heap.mo";
import "io.mo";

var L_ADDR:  i64 = 0;     # 活跃分配的地址表
var L_SIZE:  i64 = 0;     # 对应大小
var L_SEQ:   i64 = 0;     # 对应序号（第几次分配）
var L_N:     i64 = 0;     # 当前活跃条数
var L_TOT:   i64 = 0;     # 累计分配次数
var L_FREE:  i64 = 0;     # 累计释放次数
var L_PEAK:  i64 = 0;     # 活跃条数峰值
var L_BYTES: i64 = 0;     # 当前活跃字节
var L_CAP:   i64 = 0;     # 表容量
var L_OVER:  i64 = 0;     # 表溢出次数（溢出后不再记录新的，但不影响正确性）

fn leak_init() -> i64 {
    L_CAP = 8192;
    L_ADDR = malloc(L_CAP * 8);
    L_SIZE = malloc(L_CAP * 8);
    L_SEQ  = malloc(L_CAP * 8);
    if L_ADDR == 0 { return 0 - 1; }
    if L_SIZE == 0 { return 0 - 1; }
    if L_SEQ  == 0 { return 0 - 1; }
    L_N = 0; L_TOT = 0; L_FREE = 0; L_PEAK = 0; L_BYTES = 0; L_OVER = 0;
    return 0;
}

fn leak_track(p: i64, n: i64) -> i64 {
    if L_N >= L_CAP { L_OVER = L_OVER + 1; return 0; }
    store64(L_ADDR + L_N * 8, p);
    store64(L_SIZE + L_N * 8, n);
    store64(L_SEQ  + L_N * 8, L_TOT);
    L_N = L_N + 1;
    L_BYTES = L_BYTES + n;
    if L_N > L_PEAK { L_PEAK = L_N; }
    return 0;
}

fn lmalloc(n: i64) -> ptr {
    let p: i64 = malloc(n);
    if p == 0 { return 0; }
    L_TOT = L_TOT + 1;
    leak_track(p, n);
    return p;
}

fn lfree(p: i64) -> i64 {
    if p == 0 { return 0; }
    let i: i64 = 0;
    while i < L_N {
        if load64(L_ADDR + i * 8) == p {
            L_BYTES = L_BYTES - load64(L_SIZE + i * 8);
            # 用最后一条覆盖当前条（O(1) 删除，不保序）
            let last: i64 = L_N - 1;
            store64(L_ADDR + i * 8, load64(L_ADDR + last * 8));
            store64(L_SIZE + i * 8, load64(L_SIZE + last * 8));
            store64(L_SEQ  + i * 8, load64(L_SEQ  + last * 8));
            L_N = last;
            L_FREE = L_FREE + 1;
            return free(p);
        }
        i = i + 1;
    }
    # 释放一个**没被追踪**的地址（用了裸 malloc，或 double free）
    return free(p);
}

# 只清统计，不释放表 —— 用于「分段测量」：
# 先测一段代码的分配情况，清零，再测下一段。
fn leak_clear() -> i64 {
    L_N = 0; L_BYTES = 0; L_TOT = 0; L_FREE = 0; L_PEAK = 0;
    return 0;
}

fn leak_count() -> i64 { return L_N; }
fn leak_bytes() -> i64 { return L_BYTES; }

fn leak_report() -> i64 {
    print("---- 内存分配报告 ----\n");
    print("累计分配 : "); print_i64(L_TOT);    print("\n");
    print("累计释放 : "); print_i64(L_FREE);   print("\n");
    print("活跃条数 : "); print_i64(L_N);      print("\n");
    print("活跃字节 : "); print_i64(L_BYTES);  print("\n");
    print("峰值条数 : "); print_i64(L_PEAK);   print("\n");
    if L_OVER > 0 {
        print("⚠ 追踪表溢出 "); print_i64(L_OVER); print(" 次，报告不完整\n");
    }
    if L_N > 0 {
        print("⚠ 未释放的分配（前 8 条）：\n");
        let i: i64 = 0;
        while i < L_N {
            if i < 8 {
                print("  #"); print_i64(load64(L_SEQ + i * 8));
                print("  地址 "); print_i64(load64(L_ADDR + i * 8));
                print("  大小 "); print_i64(load64(L_SIZE + i * 8));
                print("\n");
            }
            i = i + 1;
        }
    } else {
        print("✓ 无泄漏\n");
    }
    return L_N;
}
