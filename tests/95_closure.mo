# 95 —— 嵌套函数与变量捕获（闭包）
#
# 嵌套函数定义在函数体内，捕获外层的局部变量与参数。
# 代码就地发射（外层用 jmp 跳过），捕获靠静态链：被调用时 [rbp] 就是
# 调用者的帧指针，本实现支持一层。
import "assert.mo";

fn outer(x: i64) -> i64 {
    let a: i64 = 10;
    fn addc(b: i64) -> i64 {
        return a + b + x;
    }
    return addc(5);
}

fn counter(x: i64) -> i64 {
    let n: i64 = 0;
    fn bump() -> i64 {
        n = n + 1;
        return n + x;
    }
    bump();
    bump();
    return bump();
}

# 捕获的变量在多次调用之间保持（同一外层栈帧）
fn accum(base: i64) -> i64 {
    let s: i64 = 0;
    fn addit(v: i64) -> i64 {
        s = s + v;
        return s;
    }
    addit(1);
    addit(2);
    addit(3);
    return s + base;
}

# 嵌套函数里再调用普通函数
fn dbl(v: i64) -> i64 { return v * 2; }
fn withcall(k: i64) -> i64 {
    fn go(v: i64) -> i64 {
        return dbl(v) + k;
    }
    return go(7);
}

fn main() -> i64 {
    assert_eq("capture local", outer(1), 16);
    assert_eq("capture local 2", outer(100), 115);
    assert_eq("capture and write", counter(10), 13);
    assert_eq("state persists", accum(100), 106);
    assert_eq("calls fn inside", withcall(5), 19);
    return test_done();
}
