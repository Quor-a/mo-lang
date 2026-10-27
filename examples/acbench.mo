# ac 基准：AC vs 朴素的操作次数对照 + 覆盖守卫
#
# 覆盖守卫很重要：v1.143 的 SAM 测试曾发现 SA_NCL=0 —— 被测文本
# **一次克隆都没发生**，于是所有只影响克隆状态的代码一行都没执行过，
# 测试却全绿。这里同样盯两个计数：
#   AC_NFB  failure 回退次数（=0 说明失配路径从未走过）
#   AC_NWR  输出链表 next 被写次数（=0 说明输出合并从未发生）

import "io.mo";
import "str.mo";
import "ac.mo";

var RS: i64 = 0;
fn rnd() -> i64 {
    RS = RS ^ (RS << 13);
    RS = RS ^ (RS >> 7);
    RS = RS ^ (RS << 17);
    if RS < 0 { RS = 0 - RS; }
    return RS;
}
fn rndn(n: i64) -> i64 { return rnd() % n; }

var PB: [256] i64 = 0;
var TB: [4096] i64 = 0;
var CH: [8] i64 = 0;
var BPA: [64] i64 = 0;

fn slen(s: ptr) -> i64 { let i: i64 = 0; while s[i] != 0 { i = i + 1; } return i; }

fn pmake(pid: i64, len: i64) -> ptr {
    let base: i64 = PB;
    let p: ptr = base + pid * 8;
    p[0] = 0;
    let j: i64 = 0;
    while j < len { strcat(p, CH[rndn(4)]); j = j + 1; }
    return p;
}

fn brute_cmp(t: ptr, np: i64, n: i64) -> i64 {
    let c: i64 = 0;
    let e: i64 = 0;
    while e < n {
        let pid: i64 = 0;
        while pid < np {
            let p: ptr = BPA[pid];
            let lp: i64 = slen(p);
            let s: i64 = e - lp + 1;
            if s >= 0 {
                let k: i64 = 0;
                while k < lp {
                    c = c + 1;
                    if t[s + k] != p[k] { k = lp; }
                    k = k + 1;
                }
            }
            pid = pid + 1;
        }
        e = e + 1;
    }
    return c;
}

fn run(nt: i64, np: i64) -> i64 {
    ac_init();
    let pid: i64 = 0;
    while pid < np {
        let p: ptr = pmake(pid, 2 + rndn(2));
        BPA[pid] = p;
        ac_add(p);
        pid = pid + 1;
    }
    ac_build();
    let t: ptr = TB;
    t[0] = 0;
    let k: i64 = 0;
    while k < nt { strcat(t, CH[rndn(4)]); k = k + 1; }
    let n: i64 = ac_scan(t);
    let acq: i64 = AC_NGO + AC_NFB;
    let bc: i64 = brute_cmp(t, np, nt);
    print("n="); print_i64(nt); print(" k="); print_i64(np);
    print("  AC查询="); print_i64(acq);
    print("  朴素比较="); print_i64(bc);
    print("  倍率="); print_i64(bc * 10 / acq / 10); print("."); print_i64(bc * 10 / acq % 10);
    print("  命中="); print_i64(n);
    print("  回退="); print_i64(AC_NFB);
    print("\n");
    return 0;
}

fn main() -> i64 {
    CH[0] = "a"; CH[1] = "b"; CH[2] = "c"; CH[3] = "d";

    print("── 经典用例 {he,she,his,hers} × \"ushers\" ──\n");
    ac_init();
    ac_add("he"); ac_add("she"); ac_add("his"); ac_add("hers");
    ac_build();
    let n: i64 = ac_scan("ushers");
    print("匹配数="); print_i64(n);
    print("  状态="); print_i64(AC_N);
    print("  边="); print_i64(AC_NE);
    print("  回退="); print_i64(AC_NFB);
    print("  合并写="); print_i64(AC_NWR);
    print("\n");

    print("── 后缀关系（输出合并是否真的发生）──\n");
    ac_init();
    ac_add("ab"); ac_add("b"); ac_add("bab");
    ac_build();
    n = ac_scan("abab");
    print("匹配数="); print_i64(n); print("  合并写="); print_i64(AC_NWR);
    print("  回退="); print_i64(AC_NFB); print("\n");

    print("── 固定 n=1000，模式数 k 变化（核心性质：AC 与 k 无关）──\n");
    RS = 20241020;
    run(1000, 4);
    run(1000, 8);
    run(1000, 16);
    run(1000, 32);
    run(1000, 64);
    print("── 固定 k=16，文本长度 n 变化（两边都线性，斜率差一个量级）──\n");
    RS = 777333;
    run(100, 16);
    run(250, 16);
    run(500, 16);
    run(1000, 16);
    return 0;
}
