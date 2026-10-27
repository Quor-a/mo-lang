# 87 —— 函数返回 ptr / 结构体，以及链式方法调用
#
# 之前返回类型只有 i64：库函数只能返回整数，于是 str_trim 这类
# 明明返回地址的函数被 sfmt 当成数字打印（只能靠 ptr(v) 绕过）。
#
# 结构体返回按 System V：第 0 字段在 rax，第 1 字段在 rdx。
# 字段数 > 2 要走隐藏指针，明确报错而不是悄悄生成错的代码。
import "assert.mo";

class Pair {
    a: i64;
    b: i64;
}
fn mk(a: i64, b: i64) -> Pair {
    let p: Pair;
    p.a = a;
    p.b = b;
    return p;
}
fn Pair_sum(self: Pair) -> i64 { return self.a + self.b; }
fn Pair_mul(self: Pair) -> i64 { return self.a * self.b; }

class One {
    v: i64;
}
fn one(x: i64) -> One {
    let o: One;
    o.v = x;
    return o;
}

fn msg() -> ptr { return "hello"; }

fn main() -> i64 {
    # 双字段结构体返回（rax + rdx）
    let q: Pair = mk(7, 9);
    assert_eq("pair a", q.a, 7);
    assert_eq("pair b", q.b, 9);

    # 单字段
    let o: One = one(42);
    assert_eq("one", o.v, 42);

    # ptr 返回：调用方知道它是字符串，不用 ptr() 转换
    let m: ptr = msg();
    assert_eq("ptr len", strlen(m), 5);

    # 链式方法调用
    assert_eq("chain sum", mk(3, 4).sum(), 7);
    assert_eq("chain mul", mk(3, 4).mul(), 12);
    assert_eq("chain again", mk(10, 20).sum(), 30);

    # 链式与变量形式结果一致
    let r: Pair = mk(5, 6);
    assert_eq("same as var", mk(5, 6).sum(), r.sum());
    return test_done();
}
