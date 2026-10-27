# expect: 0
# 151_seg —— 线段树 + 懒标记
#
# 判据设计（本测试最要紧的部分）：
#   ① **精确性**：线段树是确定性结构，答案必须 == 暴力，不是"接近"。
#      与 Bloom/CMS/HLL/qdigest 那组概率性草图相反 —— 后者断言误差上界，
#      这里断言 **0 处不一致**。
#   ② **半群性**：同一棵树同时维护 sum（可差分）与 max（**无逆元**）。
#      断言 max 与 sum 在数值上确实不同 —— 否则"维护两个量"是空转，
#      max 可能只是被写成了 sum 的别名。这是 Fenwick 结构上做不到的部分。
#   ③ **标记优先级**：rset 后 radd 与 radd 后 rset 结果不同。
#      只在两种标记交替时才发作，不报错不崩溃，只是值偏大。
#   ④ **非空转守卫**：rset 次数 > 0、SGPUSH > 0（懒标记真的下推过）、
#      值有正有负。否则"0 处不一致"可能只是"全是 0 对 0"。
#   ⑤ **结构性**：单次操作访问节点数 SGNODES = O(log n)。
#   ⑥ 越界一律报错，不静默夹紧。
#
# 参照一律是**暴力算法**（直接遍历数组），不是另一个数据结构。

import "assert.mo";
import "seg.mo";

var SEED: i64 = 0;
fn nx() -> i64 {
    SEED = SEED ^ (SEED << 13);
    SEED = SEED ^ (SEED >> 7);
    SEED = SEED ^ (SEED << 17);
    if SEED < 0 { SEED = 0 - SEED; }
    return SEED;
}
fn nxr(n: i64) -> i64 {
    if n <= 0 { return 0; }
    return (nx() % n) + 1;
}

var A: [300] i64 = 0;
var N: i64 = 64;
var H: i64 = 0;

fn bsum(l: i64, r: i64) -> i64 {
    let i: i64 = l;
    let s: i64 = 0;
    while i <= r {
        s = s + A[i];
        i = i + 1;
    }
    return s;
}

fn bmax(l: i64, r: i64) -> i64 {
    let i: i64 = l;
    let m: i64 = 0 - 999999999;
    while i <= r {
        if A[i] > m { m = A[i]; }
        i = i + 1;
    }
    return m;
}

# 抽样若干随机区间，与暴力对照
var CMPN: i64 = 0;
var NSET: i64 = 0;
var FAILN: i64 = 0;
var MAXNODE: i64 = 0;
fn chk(k: i64) -> i64 {
    let t: i64 = 0;
    while t < k {
        let l: i64 = nxr(N);
        let r: i64 = nxr(N);
        if l > r {
            let s: i64 = l;
            l = r;
            r = s;
        }
        let gs: i64 = seg_qsum(H, l, r);
        let ws: i64 = bsum(l, r);
        let gm: i64 = seg_qmax(H, l, r);
        let wm: i64 = bmax(l, r);
        CMPN = CMPN + 1;
        if gs != ws { FAILN = FAILN + 1; }
        CMPN = CMPN + 1;
        if gm != wm { FAILN = FAILN + 1; }
        if SGNODES > MAXNODE { MAXNODE = SGNODES; }
        t = t + 1;
    }
    return 0;
}

fn main() -> i64 {
    H = seg_new(N);

    # ── 初始：逐点赋值 ───────────────────────────────────
    let i: i64 = 1;
    while i <= N {
        let v: i64 = nxr(50);
        let d: i64 = seg_set(H, i, v);
        A[i] = v;
        if SGNODES > MAXNODE { MAXNODE = SGNODES; }
        i = i + 1;
    }

    let d0: i64 = chk(64);
    assert_eq("初始化后区间和/最大值 0 处不一致", FAILN, 0);

    # ── 阶段一：区间加（含负值）─────────────────────────
    let r1: i64 = 0;
    while r1 < 150 {
        let l: i64 = nxr(N);
        let r2: i64 = nxr(N);
        if l > r2 {
            let s: i64 = l;
            l = r2;
            r2 = s;
        }
        let v: i64 = nxr(41);
        v = v - 21;
        let d1: i64 = seg_radd(H, l, r2, v);
        let j: i64 = l;
        while j <= r2 {
            A[j] = A[j] + v;
            j = j + 1;
        }
        if SGNODES > MAXNODE { MAXNODE = SGNODES; }
        let d2: i64 = chk(3);
        r1 = r1 + 1;
    }
    assert_eq("阶段一（区间加）0 处不一致", FAILN, 0);

    # ── 阶段二：区间赋值（Fenwick 做不到的部分）─────────
    let r3: i64 = 0;
    while r3 < 150 {
        let l: i64 = nxr(N);
        let r4: i64 = nxr(N);
        if l > r4 {
            let s: i64 = l;
            l = r4;
            r4 = s;
        }
        let v: i64 = nxr(60);
        let d3: i64 = seg_rset(H, l, r4, v);
        let j: i64 = l;
        while j <= r4 {
            A[j] = v;
            j = j + 1;
        }
        NSET = NSET + 1;
        if SGNODES > MAXNODE { MAXNODE = SGNODES; }
        let d4: i64 = chk(3);
        r3 = r3 + 1;
    }
    assert_eq("阶段二（区间赋值）0 处不一致", FAILN, 0);
    assert_true("非空转：区间赋值确实执行了", NSET > 100);

    # ── 阶段三：混合，逼出标记优先级 ────────────────────
    let r5: i64 = 0;
    while r5 < 200 {
        let l: i64 = nxr(N);
        let r6: i64 = nxr(N);
        if l > r6 {
            let s: i64 = l;
            l = r6;
            r6 = s;
        }
        let op: i64 = nxr(3);
        let v: i64 = nxr(41);
        v = v - 21;
        if op == 1 {
            let d5: i64 = seg_radd(H, l, r6, v);
            let j: i64 = l;
            while j <= r6 {
                A[j] = A[j] + v;
                j = j + 1;
            }
        } else {
            if op == 2 {
                let d6: i64 = seg_rset(H, l, r6, v);
                let j: i64 = l;
                while j <= r6 {
                    A[j] = v;
                    j = j + 1;
                }
            } else {
                let p: i64 = nxr(N);
                let d7: i64 = seg_add(H, p, v);
                A[p] = A[p] + v;
            }
        }
        if SGNODES > MAXNODE { MAXNODE = SGNODES; }
        let d8: i64 = chk(3);
        r5 = r5 + 1;
    }
    assert_eq("阶段三（混合）0 处不一致", FAILN, 0);

    # ── 收尾：全量单点 + 全体 ────────────────────────────
    let k: i64 = 1;
    while k <= N {
        assert_eq("单点区间和", seg_qsum(H, k, k), A[k]);
        assert_eq("单点区间最大值", seg_qmax(H, k, k), A[k]);
        k = k + 1;
    }
    assert_eq("全体和", seg_total(H), bsum(1, N));
    assert_eq("全体最大值", seg_qmax(H, 1, N), bmax(1, N));

    # ── ③ 标记优先级：确定性场景，不靠随机撞 ────────────
    #   为什么必须单独写：set/add 的优先级只在两种标记**交替**时发作，
    #   而"整树操作 + 查整树"会让查询直接命中完全覆盖、直接返回 SUM、
    #   **根本不触发下推** —— 于是缺陷被掩盖。必须查**严格子区间**。
    #   （M1 变异就是靠这一段才被抓到的；随机 200 轮一次都没撞上。）
    let h2: i64 = seg_new(8);
    let e1: i64 = seg_radd(h2, 1, 8, 5);
    let e2: i64 = seg_rset(h2, 1, 8, 7);
    assert_eq("add 后 set：全体和", seg_total(h2), 56);
    assert_eq("add 后 set：子区间和（触发下推）", seg_qsum(h2, 1, 4), 28);
    assert_eq("add 后 set：子区间最大值", seg_qmax(h2, 3, 6), 7);
    let e3: i64 = seg_radd(h2, 1, 8, 3);
    assert_eq("set 后 add：全体和", seg_total(h2), 80);
    assert_eq("set 后 add：子区间和", seg_qsum(h2, 1, 4), 40);
    assert_eq("set 后 add：子区间最大值", seg_qmax(h2, 2, 5), 10);

    # ── ② 半群性：max 与 sum 确实是两个不同的量 ─────────
    let ts: i64 = seg_total(H);
    let tm: i64 = seg_qmax(H, 1, N);
    assert_true("半群性：max 不是 sum 的别名", tm != ts);
    assert_true("非空转：max 确实为正（数据有正有负才有意义）", tm > 0);

    # ── ⑤ 结构性：单次操作访问节点数 O(log n) ───────────
    # n=64 ⇒ log2 = 6；线段树区间操作访问节点数 ≤ 4·log2 n + 常数
    assert_true("结构性：单次操作节点数 O(log n)", MAXNODE <= 40);
    assert_true("结构性：节点数下界（不是空转）", MAXNODE >= 4);

    # ── ④ 懒标记真的下推过 ──────────────────────────────
    let d9: i64 = seg_rset(H, 1, N, 7);
    let d10: i64 = seg_qsum(H, 3, 9);
    assert_true("非空转：懒标记确实下推过", SGPUSH > 0);

    # ── ⑥ 越界一律报错 ──────────────────────────────────
    assert_eq("越界：l=0 报错", seg_qsum(H, 0, 5), 0 - 1);
    assert_eq("越界：r>n 报错", seg_qsum(H, 1, N + 1), 0 - 1);
    assert_eq("空区间报错", seg_qmax(H, 5, 4), 0 - 1);
    assert_eq("越界后 SGBAD 被置位", SGBAD, 1);

    print("cmps=");
    print_i64(CMPN);
    print(" fails=");
    print_i64(FAILN);
    print(" nset=");
    print_i64(NSET);
    print(" maxnode=");
    print_i64(MAXNODE);
    print(" push=");
    print_i64(SGPUSH);
    print(" total=");
    print_i64(seg_total(H));
    print(" max=");
    print_i64(seg_qmax(H, 1, N));
    print_nl();

    return test_done();
}
