# random —— 伪随机数（xorshift64）
#
# 墨语言没有时间源，也没有 /dev/urandom 封装，
# 所以默认种子是固定的 —— 这点是**确定性**的，便于测试复现。
# 要不同序列请用 srand(seed)。
#
# 只做整数随机：rand() 返回非负 i64，rand_range(n) 返回 [0, n)。

var RSTATE: i64 = 8837412947;

fn srand(seed: i64) -> i64 {
    RSTATE = seed;
    # 全零状态会让 xorshift 永远输出 0
    if RSTATE == 0 { RSTATE = 8837412947; }
    return 0;
}

# 非负 i64
fn rand() -> i64 {
    let x: i64 = RSTATE;
    x = x ^ (x << 13);
    x = x ^ (x >> 7);
    x = x ^ (x << 17);
    RSTATE = x;
    # 清掉符号位，保证非负
    if x < 0 { x = 0 - x; }
    return x;
}

# [0, n)
fn rand_range(n: i64) -> i64 {
    if n <= 0 { return 0; }
    return rand() % n;
}

# 名字带 i64 的别名：num.mo 里用它，避免与将来的大数随机混淆
fn rand_range_i64(n: i64) -> i64 { return rand_range(n); }

# [lo, hi]
fn rand_between(lo: i64, hi: i64) -> i64 {
    if hi <= lo { return lo; }
    return lo + rand_range(hi - lo + 1);
}
