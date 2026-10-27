# expect: 0
# 152_hh —— Heavy Hitters：Misra-Gries（下界） + Space-Saving（上界）
#
# 判据设计（本测试最要紧的部分）：
#   ① **夹逼**（最硬的一条）：对同时在两个表中的元素
#         mg_est(x) ≤ true(x) ≤ ss_est(x)
#      MG 是这一组草图里**唯一给下界**的（Bloom/CMS/HLL/qdigest 都不是），
#      SS 给上界。任一侧写错方向，这条立刻挂 —— 而单看任何一侧
#      "est 落在某个区间内"都可以靠放大区间混过去。
#   ② **MG 的硬保证**：est(x) ≤ true(x) ≤ est(x) + D，且 D ≤ N/k。
#      D 是**确定性**的（MG 不用哈希），所以这条是 == 级断言。
#   ③ **SS 的 err 字段是有意义的**：est(x) − err(x) ≤ true(x) ≤ est(x)。
#      只断言 "est ≥ true" 会让 err 字段变成装饰。
#   ④ **不漏**：f(x) > N/k 的元素必在两个表中（两边各自的定理）。
#   ⑤ **非空转守卫**（否则上面全部平凡成立）：
#        - 必须发生过减量（MG_DEC > 0）与替换（SS_REPL > 0）
#        - 必须存在 x 使 mg_est ≠ true（否则 MG 退化成精确计数器）
#        - 必须存在 x 使 ss_est ≠ true
#        - 必须存在元素**不在**表中（否则表没满过，替换/减量逻辑没被执行）
#   ⑥ **ss_est 对不在表中的元素返回 −1 而不是 0**
#      —— 返回 0 会让人误读成"它出现了 0 次"，那是假阴。
#
# 参照是**精确直方图**（值域 0..999，直接计数），不是另一个近似算法。

import "assert.mo";
import "hh.mo";

var SSEED: i64 = 0;
fn nx() -> i64 {
    SSEED = SSEED ^ (SSEED << 13);
    SSEED = SSEED ^ (SSEED >> 7);
    SSEED = SSEED ^ (SSEED << 17);
    if SSEED < 0 { SSEED = 0 - SSEED; }
    return SSEED;
}
fn nxr(n: i64) -> i64 {
    if n <= 0 { return 0; }
    return nx() % n;
}

# ── 精确直方图（参照） ─────────────────────────────────────
var TRUE: [1000] i64 = 0;

# ── 测试用循环变量（**绝不能**用 HH1..HH4 / HHF1 / HHA1 / HHQ1 / HHM1） ──
var TI: i64 = 0;
var TJ: i64 = 0;
var TK: i64 = 0;
var TV: i64 = 0;

var NPLAN: i64 = 0;      # 实际喂入总权重
var DSEEN: i64 = 0;      # TRUE > 0 的元素个数（覆盖基准）

# 诊断计数
var D_MGLE: i64 = 0;     # 满足 mg_est ≤ true 的元素数
var D_SSGE: i64 = 0;     # 满足 true ≤ ss_est 的元素数
var D_BRACK: i64 = 0;    # 夹逼成立的元素数
var D_INMG: i64 = 0;     # 在 MG 表中的元素数
var D_INSS: i64 = 0;     # 在 SS 表中的元素数
var D_MGEX: i64 = 0;     # mg_est ≠ true 的元素数（非空转）
var D_SSEX: i64 = 0;     # ss_est ≠ true 的元素数（非空转）
var D_OUTSS: i64 = 0;    # 不在 SS 表中的元素数（非空转）

# ── 喂入一个元素并同步精确直方图 ────────────────────────────
fn feed(x: i64, c: i64) -> i64 {
    TRUE[x] = TRUE[x] + c;
    hh_add(x, c);
    NPLAN = NPLAN + c;
    return 0;
}

fn clr_hist() -> i64 {
    TI = 0;
    while TI < 1000 {
        TRUE[TI] = 0;
        TI = TI + 1;
    }
    return 0;
}

# ── 构造并喂入一条流 ───────────────────────────────────────
fn build(total: i64) -> i64 {
    clr_hist();
    hh_clear();
    NPLAN = 0;

    # 重击者（f > N/k）
    feed(1, 400);
    feed(2, 200);
    feed(3, 100);
    feed(10, 80);
    feed(11, 80);
    feed(12, 80);
    feed(13, 80);
    # 中等：低于 N/k，**不保证**在表里（验证"不在表"确实发生过）
    feed(4, 50);
    feed(5, 50);
    feed(6, 50);
    feed(7, 50);
    feed(8, 50);
    feed(9, 50);
    feed(14, 40);
    feed(15, 40);
    feed(16, 40);
    feed(17, 40);

    # 尾巴：随机值域 100..999（每个都很轻，不可能成为重击者）
    while NPLAN < total {
        TV = 100 + nxr(900);
        feed(TV, 1);
    }
    return 0;
}

# ── 遍历全部值域，逐条核对四个界 ────────────────────────────
fn check_all() -> i64 {
    D_MGLE = 0;
    D_SSGE = 0;
    D_BRACK = 0;
    D_INMG = 0;
    D_INSS = 0;
    D_MGEX = 0;
    D_SSEX = 0;
    D_OUTSS = 0;
    DSEEN = 0;

    TI = 0;
    while TI < 1000 {
        if TRUE[TI] > 0 {
            DSEEN = DSEEN + 1;
            TK = mg_est(TI);
            TJ = ss_est(TI);

            if mg_has(TI) == 1 { D_INMG = D_INMG + 1; }
            if TJ >= 0 { D_INSS = D_INSS + 1; } else { D_OUTSS = D_OUTSS + 1; }

            # ① MG 下界：est ≤ true（对所有出现过的元素，含不在表中的 est=0）
            if TK <= TRUE[TI] { D_MGLE = D_MGLE + 1; }
            if TK != TRUE[TI] { D_MGEX = D_MGEX + 1; }

            # ② MG 上界：true ≤ est + D
            if TRUE[TI] > TK + mg_dec() {
                assert_eq("MG 上界被突破", TI, 0 - 1);
            }

            if TJ >= 0 {
                # ③ SS 上界：true ≤ est
                if TRUE[TI] <= TJ { D_SSGE = D_SSGE + 1; }
                if TJ != TRUE[TI] { D_SSEX = D_SSEX + 1; }

                # ④ SS 的 err 是 over-estimate 上界：est − err ≤ true
                if TJ - ss_err(TI) > TRUE[TI] {
                    assert_eq("SS err 界被突破", TI, 0 - 2);
                }

                # ⑤ SS 误差不超过表中最小 count
                if TJ - TRUE[TI] > ss_min() {
                    assert_eq("SS 误差超过 min", TI, 0 - 3);
                }
            }

            # ⑥ 夹逼：mg_est ≤ true ≤ ss_est
            if TK <= TRUE[TI] {
                if TJ >= 0 {
                    if TRUE[TI] <= TJ { D_BRACK = D_BRACK + 1; }
                }
            }

            # ⑦ 不漏（MG）：f > D ⟹ 在表中
            if TRUE[TI] > mg_dec() {
                if mg_has(TI) != 1 {
                    assert_eq("MG 漏掉重击者", TI, 0 - 4);
                }
            }
            # ⑧ 不漏（SS）：f·k > N ⟹ 在表中
            if TRUE[TI] * HH_K > NPLAN {
                if TJ < 0 {
                    assert_eq("SS 漏掉重击者", TI, 0 - 5);
                }
            }
        }
        TI = TI + 1;
    }
    return 0;
}

fn main() -> i64 {
    SSEED = 88172645463325252;

    # ══ 场景 A：大流，k=64 ══════════════════════════════════
    HH_K = 64;
    build(4000);

    assert_eq("A: 总权重", hh_total(), NPLAN);
    assert_eq("A: 参数合法", HHBAD, 0);

    check_all();

    # 覆盖：MG 下界必须对**每一个**出现过的元素成立，一个都不能少
    assert_eq("A: MG 下界全覆盖", D_MGLE, DSEEN);
    # SS 上界只对"在表中的"元素有定义
    assert_eq("A: SS 上界全覆盖", D_SSGE, D_INSS);
    assert_true("A: 夹逼样本 > 0", D_BRACK > 0);

    # 结构性：MG 的减量 D 满足 D·k ≤ N（硬保证，不是"接近"）
    if mg_dec() * HH_K > NPLAN {
        assert_eq("A: D·k ≤ N 被突破", mg_dec(), 0 - 6);
    }
    assert_eq("A: D·k ≤ N", 1, 1);

    # 非空转守卫
    assert_true("A: 发生过减量", mg_dec() > 0);
    assert_true("A: 发生过替换", ss_repl() > 0);
    assert_true("A: MG 不是精确计数器", D_MGEX > 0);
    assert_true("A: SS 不是精确计数器", D_SSEX > 0);
    assert_true("A: 存在不在表中的元素", D_OUTSS > 0);

    # SS 永不减槽 ⟹ 一定恰好填满（替换是"换人"不是"减员"）
    assert_eq("A: SS 表满", ss_used(), HH_K);
    # MG 会靠减量清槽 ⟹ 只断言上界 + 非空。
    # 第一版我写成了 == HH_K，实测 got 29 —— 那不是缺陷，
    # 是**断言写错了**：把 SS 的性质套到了 MG 上。
    if mg_used() > HH_K {
        assert_eq("A: MG 槽数上界被突破", mg_used(), 0 - 8);
    }
    assert_true("A: MG 槽数 > 0", mg_used() > 0);
    assert_true("A: MG 槽数 < k（减量真的清过槽）", mg_used() < HH_K);

    # 明确的重击者必须都在
    assert_eq("A: 重击者 1 在 MG", mg_has(1), 1);
    assert_eq("A: 重击者 2 在 MG", mg_has(2), 1);
    assert_eq("A: 重击者 3 在 MG", mg_has(3), 1);
    assert_eq("A: 重击者 10 在 MG", mg_has(10), 1);
    assert_eq("A: 重击者 1 在 SS", ss_has(1), 1);
    assert_eq("A: 重击者 2 在 SS", ss_has(2), 1);
    assert_eq("A: 重击者 3 在 SS", ss_has(3), 1);
    assert_eq("A: 重击者 10 在 SS", ss_has(10), 1);

    # ── 实测数字（供 tools/hhtest.sh 与 docs/hh.md 引用）──────
    # 这些不是装饰：hhtest.sh 会检查它们存在，
    # 而"夹逼"的具体数值比一句"通过"有说服力得多。
    print("N=");
    print_i64(NPLAN);
    print(" k=");
    print_i64(HH_K);
    print(" Noverk=");
    print_i64(NPLAN / HH_K);
    print(" mg_dec=");
    print_i64(mg_dec());
    print(" mg_used=");
    print_i64(mg_used());
    print(" ss_used=");
    print_i64(ss_used());
    print(" ss_min=");
    print_i64(ss_min());
    print(" ss_repl=");
    print_i64(ss_repl());
    print(" seen=");
    print_i64(DSEEN);
    print(" inMG=");
    print_i64(D_INMG);
    print(" inSS=");
    print_i64(D_INSS);
    print(" bracket=");
    print_i64(D_BRACK);
    print_nl();

    # 夹逼的三元组：est_MG ≤ true ≤ est_SS，逐个重击者打印
    TK = 1;
    while TK <= 3 {
        print(" clamp[");
        print_i64(TK);
        print("] mg=");
        print_i64(mg_est(TK));
        print(" true=");
        print_i64(TRUE[TK]);
        print(" ss=");
        print_i64(ss_est(TK));
        print(" sserr=");
        print_i64(ss_err(TK));
        print_nl();
        TK = TK + 1;
    }

    # ── 精确定量：重击者从未被逐出 ⇒ 它**每次减量都跟着减 1** ──
    #    于是 est(x) 必然恰好等于 true(x) − D，误差不多不少就是 D。
    #    实测 400−349 / 200−149 / 100−49 三个都是 51 = mg_dec。
    #    这比"est ≤ true ≤ est+D"强得多：界只给范围，这条给**等号**。
    assert_eq("A: 重击者 1 低估量 == D", TRUE[1] - mg_est(1), mg_dec());
    assert_eq("A: 重击者 2 低估量 == D", TRUE[2] - mg_est(2), mg_dec());
    assert_eq("A: 重击者 3 低估量 == D", TRUE[3] - mg_est(3), mg_dec());

    # 同理，从未被替换过的 SS 槽是**精确**的：est == true 且 err == 0。
    # （SS 的误差只来自"被吸收"的那部分，重击者没被吸收过）
    assert_eq("A: SS 对重击者 1 精确", ss_est(1), TRUE[1]);
    assert_eq("A: SS 对重击者 1 err=0", ss_err(1), 0);

    # ══ 场景 B：确定性小场景，k=4 ═══════════════════════════
    # 随机会漏掉特定序列，这里手工构造一个能精确预期的流。
    HH_K = 4;
    clr_hist();
    hh_clear();
    NPLAN = 0;
    feed(1, 20);
    feed(2, 15);
    feed(3, 10);
    feed(4, 5);
    feed(5, 1);

    # N = 51, k = 4, N/k = 12.75 → f > 12.75 的是 1(20) 和 2(15)
    assert_eq("B: N", NPLAN, 51);
    assert_eq("B: 重击者 1 在 MG", mg_has(1), 1);
    assert_eq("B: 重击者 2 在 MG", mg_has(2), 1);
    assert_eq("B: 重击者 1 在 SS", ss_has(1), 1);
    assert_eq("B: 重击者 2 在 SS", ss_has(2), 1);

    check_all();
    assert_true("B: 夹逼成立", D_BRACK > 0);
    assert_eq("B: MG 下界全覆盖", D_MGLE, DSEEN);
    if mg_dec() * HH_K > NPLAN {
        assert_eq("B: D·k ≤ N 被突破", mg_dec(), 0 - 7);
    }

    # ══ 场景 C：全部元素都相同（退化流） ══════════════════════
    HH_K = 64;
    clr_hist();
    hh_clear();
    NPLAN = 0;
    feed(7, 500);

    assert_eq("C: 单元素 MG 精确", mg_est(7), 500);
    assert_eq("C: 单元素 SS 精确", ss_est(7), 500);
    assert_eq("C: SS err = 0", ss_err(7), 0);
    assert_eq("C: 未发生替换", ss_repl(), 0);
    assert_eq("C: 未发生减量", mg_dec(), 0);
    assert_eq("C: 其它值不在表", ss_has(8), 0);
    assert_eq("C: 不在表返回 -1", ss_est(8), 0 - 1);
    assert_eq("C: MG 不在表返回 0", mg_est(8), 0);

    # ══ 场景 D：参数校验 ════════════════════════════════════
    assert_eq("D: c=0 被拒", hh_add(1, 0), 0 - 1);
    assert_eq("D: HHBAD 置位", HHBAD, 1);
    assert_eq("D: c<0 被拒", hh_add(1, 0 - 3), 0 - 1);

    return test_done();
}
