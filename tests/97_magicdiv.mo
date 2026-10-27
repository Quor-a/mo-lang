# 97 —— 任意常量除数的魔数优化（乘法倒数代替 idiv）
#
# 验证方式：与「除数是变量」的路径**逐值对照**。变量除数走 idiv（未优化），
# 常量除数走魔数 —— 两者必须完全一致。
#
# 🔴 为什么要穷举而不只是测几个值：魔数最经典的错法只在**负数**上暴露
#    （最后一步是 q -= (n>>63)，方向搞反会得到 -4 而不是 -2）。
import "assert.mo";

fn main() -> i64 {
    let d3: i64 = 3; let d7: i64 = 7; let d10: i64 = 10; let d100: i64 = 100;
    let d1000: i64 = 1000; let d3000: i64 = 3000; let d704: i64 = 704;
    let d65537: i64 = 65537; let d2: i64 = 2; let d1: i64 = 1; let d256: i64 = 256;
    let i: i64 = 0 - 2000;
    while i <= 2000 {
        assert_eq("/7", i / 7, i / d7);         assert_eq("%7", i % 7, i % d7);
        assert_eq("/3", i / 3, i / d3);         assert_eq("%3", i % 3, i % d3);
        assert_eq("/10", i / 10, i / d10);      assert_eq("%10", i % 10, i % d10);
        assert_eq("/100", i / 100, i / d100);   assert_eq("%100", i % 100, i % d100);
        assert_eq("/1000", i / 1000, i / d1000);
        assert_eq("/3000", i / 3000, i / d3000);
        assert_eq("/704", i / 704, i / d704);   assert_eq("%704", i % 704, i % d704);
        assert_eq("/65537", i / 65537, i / d65537);
        assert_eq("/2", i / 2, i / d2);         assert_eq("%2", i % 2, i % d2);
        assert_eq("/256", i / 256, i / d256);
        assert_eq("/1", i / 1, i / d1);         assert_eq("%1", i % 1, i % d1);
        i = i + 1;
    }
    # 负数除数：n/(-d) == -(n/d)，而 n%(-d) == n%d
    let j: i64 = 0 - 200;
    while j <= 200 {
        assert_eq("/(-7)", j / (0 - 7), 0 - (j / d7));
        assert_eq("%(-7)", j % (0 - 7), j % d7);
        j = j + 1;
    }
    # 边界：MIN / MAX
    let mn: i64 = 0 - 9223372036854775807 - 1;
    let mx: i64 = 9223372036854775807;
    assert_eq("min/7", mn / 7, mn / d7);    assert_eq("min%7", mn % 7, mn % d7);
    assert_eq("max/7", mx / 7, mx / d7);    assert_eq("max%7", mx % 7, mx % d7);
    assert_eq("min/3", mn / 3, mn / d3);
    assert_eq("min/1", mn / 1, mn);
    # 🔴 这一条期望原本写的是 0 —— **错的**，而且一直没人发现：
    #    因为本文件此前 `return 0`，assert_eq 的返回值被丢弃，
    #    断言结果从不进退出码（详见 docs/float_literal.md 的"空转断言"一节）。
    #    -7/2 按 C 截断语义是 -3（不是 0，也不是 Python 的 -4）。
    assert_eq("known -7/2", (0 - 7) / 2, 0 - 3);
    assert_eq("known 17/7", 17 / 7, 2);
    assert_eq("known -17%7", (0 - 17) % 7, 0 - 3);
    return test_done();
}
