# random：确定性与范围
# expect: 1
import "random.mo";
import "assert.mo";

fn main() -> i64 {
    # 默认种子是固定的 —— 这是刻意的，便于测试复现
    srand(42);
    let a1: i64 = rand();
    srand(42);
    let a2: i64 = rand();
    assert_eq("deterministic", a1 == a2, 1);

    # 同一种子下序列可复现
    srand(7);
    let s1: i64 = rand();
    let s2: i64 = rand();
    srand(7);
    assert_eq("seq1", rand(), s1);
    assert_eq("seq2", rand(), s2);

    # 非负
    srand(12345);
    let i: i64 = 0;
    let neg: i64 = 0;
    while i < 200 {
        if rand() < 0 { neg = neg + 1; }
        i = i + 1;
    }
    assert_eq("non-negative", neg, 0);

    # rand_range 落在 [0, n)
    srand(99);
    let bad: i64 = 0;
    i = 0;
    while i < 500 {
        let v: i64 = rand_range(10);
        if v < 0 { bad = bad + 1; }
        if v >= 10 { bad = bad + 1; }
        i = i + 1;
    }
    assert_eq("range", bad, 0);

    # rand_between 落在 [lo, hi]
    srand(2024);
    bad = 0;
    i = 0;
    while i < 500 {
        let w: i64 = rand_between(5, 15);
        if w < 5 { bad = bad + 1; }
        if w > 15 { bad = bad + 1; }
        i = i + 1;
    }
    assert_eq("between", bad, 0);

    # 分布：10000 次 rand_range(4) 应当四个值都出现
    srand(31337);
    let c0: i64 = 0;
    let c1: i64 = 0;
    let c2: i64 = 0;
    let c3: i64 = 0;
    i = 0;
    while i < 4000 {
        let r: i64 = rand_range(4);
        if r == 0 { c0 = c0 + 1; }
        if r == 1 { c1 = c1 + 1; }
        if r == 2 { c2 = c2 + 1; }
        if r == 3 { c3 = c3 + 1; }
        i = i + 1;
    }
    assert_true("all4_seen", c0 > 0);
    assert_true("all4_seen2", c1 > 0);
    assert_true("all4_seen3", c2 > 0);
    assert_true("all4_seen4", c3 > 0);

    let t_failed: i64 = test_done();
    if t_failed != 0 { return 2; }
    return 1;
}
