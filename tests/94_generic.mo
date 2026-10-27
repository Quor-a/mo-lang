# 94 —— 泛型函数与单态化（generic / instantiate）
#
# 一份源码生成多份类型特化。做法：把函数体源码文本存下来，instantiate
# 时把类型参数名替换成实际类型，重新解析一遍 —— 不用 IR，也不用改类型系统。
import "assert.mo";

generic fn maxg<T>(a: T, b: T) -> T {
    if a > b { return a; }
    return b;
}
instantiate maxg(i64) as maxi;
instantiate maxg(f64) as maxf;

generic fn addg<T>(a: T, b: T) -> T {
    return a + b;
}
instantiate addg(i64) as addi;

# 两个类型参数
generic fn pick<T, U>(a: T, b: U) -> T {
    return a;
}
instantiate pick(i64, i64) as pickii;

# 替换必须在**标识符边界**上发生：形参 Tx 不能被当成 T 替换掉
generic fn keepT<T>(a: T, Tx: i64) -> i64 {
    return Tx;
}
instantiate keepT(i64) as keepi;

# 泛型体里可以调用普通函数
fn twice(x: i64) -> i64 { return x * 2; }
generic fn applyg<T>(a: T) -> i64 {
    return twice(a);
}
instantiate applyg(i64) as applyi;

fn main() -> i64 {
    assert_eq("max i64 a", maxi(3, 9), 9);
    assert_eq("max i64 b", maxi(7, 2), 7);
    assert_eq("add i64", addi(20, 22), 42);
    assert_eq("two params", pickii(5, 8), 5);
    assert_eq("Tx not replaced", keepi(1, 77), 77);
    assert_eq("calls fn", applyi(21), 42);

    # f64 实例：转成 i64 再断言（4.25 * 2 = 8.5 → fint 得 8）
    assert_eq("max f64", fint(maxf(1.5, 4.25) * 2), 8);
    assert_eq("max f64 b", fint(maxf(9.5, 2.25) * 2), 19);
    return test_done();
}
