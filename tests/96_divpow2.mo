# 96 —— 除以/取模 2 的幂：移位代替 idiv（强度削减）
#
# 验证方式：与「除数是变量」的路径**逐值对照**。那条路走 idiv（未优化），
# 这条走移位 —— 两者结果必须完全一致。只测几个值是不够的，
# 因为最经典的错法（漏掉负数偏置）只在负数上暴露。
import "assert.mo";

fn main() -> i64 {
    let d2:  i64 = 2;
    let d8:  i64 = 8;
    let d1:  i64 = 1;
    let d256: i64 = 256;
    let n: i64 = 0 - 40;
    while n <= 40 {
        assert_eq("n/2",   n / 2,   n / d2);
        assert_eq("n/8",   n / 8,   n / d8);
        assert_eq("n/1",   n / 1,   n / d1);
        assert_eq("n/256", n / 256, n / d256);
        assert_eq("n%2",   n % 2,   n % d2);
        assert_eq("n%8",   n % 8,   n % d8);
        assert_eq("n%1",   n % 1,   n % d1);
        assert_eq("n%256", n % 256, n % d256);
        n = n + 1;
    }
    # 🔴 负数偏置：sar 向下取整、C 除法向零截断，两者只在负数上分岔
    assert_eq("-1/2",  (0 - 1) / 2,  0);
    assert_eq("-7/8",  (0 - 7) / 8,  0);
    assert_eq("-8/8",  (0 - 8) / 8,  0 - 1);
    assert_eq("-9/8",  (0 - 9) / 8,  0 - 1);
    assert_eq("-1%2",  (0 - 1) % 2,  0 - 1);
    assert_eq("-7%8",  (0 - 7) % 8,  0 - 7);
    # 大数与 k=31 边界
    assert_eq("big/1024",   1000000 / 1024, 976);
    assert_eq("-big/1024",  (0 - 1000000) / 1024, 0 - 976);
    assert_eq("k31",        2147483647 / 2147483648, 0);
    # 非 2 的幂仍走 idiv，结果必须一致（回归保护）
    let d7: i64 = 7;
    assert_eq("n%7", 17 % 7, 17 % d7);
    assert_eq("n/7", 17 / 7, 17 / d7);
    return test_done();
}
