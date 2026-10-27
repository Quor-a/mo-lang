# 126 —— f64 数学库 + IEEE754 unordered 比较语义        # expect: 0
#
# ── 本测试为什么存在 ────────────────────────────────────────
#   ① **NaN 比较语义**（编译器级，1.114 修）
#      f64 比较走 ucomisd + setcc，但裸 setcc 在 **unordered**（任一操作数
#      为 NaN，此时 ZF=PF=CF=1）下给出：
#        sete/setb/setbe → 1（应为 0）   setne → 0（应为 1）
#      于是 `x != x` 这个**最惯用的 NaN 判据恒为假** —— 不报错、不崩溃，
#      只是所有 isnan 检测、排序、最值、断言静默失效。
#      实测修复前：nan == nan 得 1、nan != nan 得 0、nan < 1.0 得 1。
#
#   ② 数学函数的**特殊值语义**（不是精度）
#      精度由 tools/fmathtest.sh 与 Python 逐点比对（ULP），
#      这里只管 sqrt(-1)=NaN、log(0)=-Inf 这类"边界该给什么"。
#
# ── 判据为什么是具体值而不是"能跑"────────────────────────
#   特殊值错了不崩溃，只是返回一个**看起来合理**的数。
#   所以每条断言都写明确切的期望。

import "assert.mo";
import "io.mo";
import "fmath.mo";

# ⚠️ 全局变量只支持 i64 / 数组，f64 常量必须在 main 内 let。

fn main() -> i64 {
    let NAN_: f64 = fm_nan();
    let INF_: f64 = fm_inf();

    # ══ ① IEEE754 unordered 比较语义 ══════════════════════
    # 六个比较在 NaN 参与下必须给出 false（除 != 为 true）。
    let r: i64 = 0;
    if NAN_ == NAN_ { r = 1; } else { r = 0; }
    assert_eq("nan == nan 必须为假", r, 0);
    if NAN_ != NAN_ { r = 1; } else { r = 0; }
    assert_eq("nan != nan 必须为真（isnan 的唯一判据）", r, 1);
    if NAN_ < 1.0 { r = 1; } else { r = 0; }
    assert_eq("nan < 1.0 必须为假", r, 0);
    if NAN_ > 1.0 { r = 1; } else { r = 0; }
    assert_eq("nan > 1.0 必须为假", r, 0);
    if NAN_ <= 1.0 { r = 1; } else { r = 0; }
    assert_eq("nan <= 1.0 必须为假", r, 0);
    if NAN_ >= 1.0 { r = 1; } else { r = 0; }
    assert_eq("nan >= 1.0 必须为假", r, 0);
    if 1.0 <= NAN_ { r = 1; } else { r = 0; }
    assert_eq("1.0 <= nan 必须为假（另一侧操作数）", r, 0);
    if 1.0 > NAN_ { r = 1; } else { r = 0; }
    assert_eq("1.0 > nan 必须为假（另一侧操作数）", r, 0);

    # 非 NaN 的比较不受影响（防止修过头：把正常比较也改坏）
    if 1.5 < 2.5 { r = 1; } else { r = 0; }
    assert_eq("1.5 < 2.5", r, 1);
    if 0.0 - 1.0 < 0.0 - 2.0 { r = 1; } else { r = 0; }
    assert_eq("-1 < -2 必须为假（负数比较不能退化成整数比较）", r, 0);
    if INF_ > 1.0 { r = 1; } else { r = 0; }
    assert_eq("inf > 1.0", r, 1);
    if INF_ == INF_ { r = 1; } else { r = 0; }
    assert_eq("inf == inf", r, 1);

    # ══ ② 分类函数 ══════════════════════════════════════
    assert_eq("fm_isnan(nan)", fm_isnan(NAN_), 1);
    assert_eq("fm_isnan(1.0)", fm_isnan(1.0), 0);
    assert_eq("fm_isinf(inf)", fm_isinf(INF_), 1);
    assert_eq("fm_isinf(-inf)", fm_isinf(0.0 - INF_), 1);
    assert_eq("fm_isinf(1.0)", fm_isinf(1.0), 0);
    assert_eq("fm_isfinite(inf)", fm_isfinite(INF_), 0);
    assert_eq("fm_isfinite(nan)", fm_isfinite(NAN_), 0);
    assert_eq("fm_isfinite(1.0)", fm_isfinite(1.0), 1);
    assert_eq("fm_signbit(-2.0)", fm_signbit(0.0 - 2.0), 1);
    assert_eq("fm_signbit(2.0)", fm_signbit(2.0), 0);

    # ══ ③ sqrt 特殊值 ═══════════════════════════════════
    assert_eq("sqrt(-1) 必须是 NaN", fm_isnan(fm_sqrt(0.0 - 1.0)), 1);
    assert_eq("sqrt(0) == 0", fbits(fm_sqrt(0.0)), 0);
    assert_eq("sqrt(inf) == inf", fm_isinf(fm_sqrt(INF_)), 1);
    assert_eq("sqrt(nan) 传播", fm_isnan(fm_sqrt(NAN_)), 1);
    assert_eq("sqrt(1) == 1", fbits(fm_sqrt(1.0)), 4607182418800017408);
    assert_eq("sqrt(4) == 2", fbits(fm_sqrt(4.0)), 4611686018427387904);

    # ══ ④ exp / log 特殊值 ══════════════════════════════
    assert_eq("exp(0) == 1", fbits(fm_exp(0.0)), 4607182418800017408);
    assert_eq("exp(inf) == inf", fm_isinf(fm_exp(INF_)), 1);
    assert_eq("exp(-inf) == 0", fbits(fm_exp(0.0 - INF_)), 0);
    assert_eq("exp(nan) 传播", fm_isnan(fm_exp(NAN_)), 1);
    assert_eq("log(1) == 0", fbits(fm_log(1.0)), 0);
    assert_eq("log(0) == -inf", fm_isinf(fm_log(0.0)), 1);
    assert_eq("log(-1) 必须是 NaN", fm_isnan(fm_log(0.0 - 1.0)), 1);
    assert_eq("log(inf) == inf", fm_isinf(fm_log(INF_)), 1);

    # ══ ⑤ 三角特殊值 ════════════════════════════════════
    assert_eq("sin(0) == 0", fbits(fm_sin(0.0)), 0);
    assert_eq("cos(0) == 1", fbits(fm_cos(0.0)), 4607182418800017408);
    assert_eq("sin(inf) 必须是 NaN", fm_isnan(fm_sin(INF_)), 1);
    assert_eq("cos(inf) 必须是 NaN", fm_isnan(fm_cos(INF_)), 1);
    # 周期性：sin(x + 2π) == sin(x)（在 |x| 小、规约误差可忽略时）
    # 2π 写成字面量只有 8 位小数（编译器截断），所以阈值取 1e-6 而非 1e-9
    let d: f64 = fm_sin(1.0) - fm_sin(1.0 + 6.28318531);
    assert_eq("sin 的 2π 周期（小参数）", fm_fabs(d) < 1.0 / 1000000.0, 1);

    # ══ ⑥ pow 特殊值 ════════════════════════════════════
    assert_eq("pow(x, 0) == 1", fbits(fm_pow(2.5, 0.0)), 4607182418800017408);
    assert_eq("pow(1, y) == 1", fbits(fm_pow(1.0, 123.0)), 4607182418800017408);
    assert_eq("pow(-1, 0.5) 必须是 NaN", fm_isnan(fm_pow(0.0 - 1.0, 0.5)), 1);
    assert_eq("pow(2, 3) == 8（整数指数精确，不走 exp/log）", fbits(fm_pow(2.0, 3.0)), fbits(8.0));

    # ══ ⑦ 取整：负数方向是最容易错的地方 ════════════════
    assert_eq("floor(-2.5) == -3", fbits(fm_floor(0.0 - 2.5)), fbits(0.0 - 3.0));
    assert_eq("ceil(-2.5) == -2", fbits(fm_ceil(0.0 - 2.5)), fbits(0.0 - 2.0));
    assert_eq("floor(2.5) == 2", fbits(fm_floor(2.5)), fbits(2.0));
    assert_eq("ceil(2.5) == 3", fbits(fm_ceil(2.5)), fbits(3.0));
    assert_eq("round(2.5) == 3（半值远离零）", fbits(fm_round(2.5)), fbits(3.0));
    assert_eq("round(-2.5) == -3", fbits(fm_round(0.0 - 2.5)), fbits(0.0 - 3.0));
    assert_eq("trunc(-2.5) == -2（向零）", fbits(fm_trunc(0.0 - 2.5)), fbits(0.0 - 2.0));

    # ══ ⑧ 位级原语 ══════════════════════════════════════
    assert_eq("ldexp(1, 10) == 1024", fbits(fm_ldexp(1.0, 10)), fbits(1024.0));
    assert_eq("ldexp(1, -10) 精确地缩小", fbits(fm_ldexp(1.0, 0 - 10)), fbits(1.0/1024.0));
    assert_eq("exponent(1024) == 10", fm_exponent(1024.0), 10);
    assert_eq("exponent(1) == 0", fm_exponent(1.0), 0);
    assert_eq("ldexp 后 exponent 复原", fm_exponent(fm_ldexp(1.5, 37)), 37);
    assert_eq("fabs(-3.5) == 3.5", fbits(fm_fabs(0.0 - 3.5)), fbits(3.5));

    # ══ ⑨ 单调性（算法正确性的间接但不充分的证据）══════
    let prev: f64 = 0.0 - 1000000.0;
    let mono: i64 = 1;
    let i: i64 = 0;
    while i < 40 {
        let x: f64 = f64(i) * 0.1;
        let y: f64 = fm_exp(x);
        if y <= prev { mono = 0; }
        prev = y;
        i = i + 1;
    }
    assert_eq("exp 严格单调递增（40 点）", mono, 1);

    return test_done();
}
