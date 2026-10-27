import "scat.mo";
import "io.mo";

# 朴素拼接的真实代价：每次都要把已有前缀**重抄一遍**。
#
#   s = s + "x"   做 n 次
#   第 i 次复制 i 字节  →  总计 n(n+1)/2
#
# 也就是说 n 翻倍，复制量 **4 倍**。这是 O(n^2)，不是 O(n)。
# 本示例把这条曲线量出来，并演示 region 怎么把内存收回来。

# 跑一轮，返回本轮复制的字节数。
fn bench(n: i64) -> i64 {
    let c0: i64 = scat_copy();
    let s: str = "";
    let i: i64 = 0;
    while i < n {
        s = s + "x";
        i = i + 1;
    }
    let c1: i64 = scat_copy();

    # 结果必须真的是 n 个 'x' —— 长度对了不等于内容对了
    let bad: i64 = 0;
    if scat_len(s) != n { bad = 1; }
    let j: i64 = 0;
    while j < n {
        if s[j] != 120 { bad = 1; }
        j = j + 1;
    }
    if s[n] != 0 { bad = 1; }

    print_i64(n);
    print("  复制 ");
    print_i64(c1 - c0);
    print("  长度 ");
    print_i64(scat_len(s));
    print("  used ");
    print_i64(scat_used());
    print("  cap ");
    print_i64(scat_cap());
    if bad == 1 { print("  ✗ 内容错"); } else { print("  ✓"); }
    print("\n");
    return c1 - c0;
}

fn main() -> i64 {
    print("== 朴素拼接：复制量随 n 二次增长 ==\n");
    let a: i64 = bench(100);
    let b: i64 = bench(200);
    let c: i64 = bench(400);
    let d: i64 = bench(800);

    print("\n比值（n 翻倍应约为 4）：\n");
    print("  200/100 = ");
    print_i64(b * 100 / a);
    print(" /100\n  400/200 = ");
    print_i64(c * 100 / b);
    print(" /100\n  800/400 = ");
    print_i64(d * 100 / c);
    print(" /100\n");

    print("\n== region：整批丢弃，内存不还给内核但可复用 ==\n");
    print("reset 前  used = ");
    print_i64(scat_used());
    print("  cap = ");
    print_i64(scat_cap());
    print("  brk 次数 = ");
    print_i64(scat_mov());
    print("\n");

    scat_reset();
    print("reset 后  used = ");
    print_i64(scat_used());
    print("  cap = ");
    print_i64(scat_cap());
    print("  brk 次数 = ");
    print_i64(scat_mov());
    print("\n");

    let m0: i64 = scat_mov();
    let e: i64 = bench(800);
    let m1: i64 = scat_mov();
    print("\n复用：reset 后再跑 800 次\n  brk 次数 ");
    print_i64(m0);
    print(" -> ");
    print_i64(m1);
    if m1 == m0 {
        print("  ✓ 没有再向内核要内存\n");
    } else {
        print("  ✗ 又向内核要了内存\n");
    }
    if e == d { print("  复制量与首次相同 ✓\n"); } else { print("  ✗ 复制量不一致\n"); }

    print("\nerr = ");
    print_i64(scat_err());
    print("\n");
    return 0;
}
