# expect: 64
# 测试：mo2x C 后端 lambda 表达式 + ptr 变量 fnptr 调用（v1.1166）
fn invoke(f: ptr) -> i64 {
    return f(5);
}

fn main() -> i64 {
    let a: ptr = fn(x: i64) -> i64 {
        return x * 7;          # 35
    };
    let part1: i64 = invoke(a);            # 35
    let b: ptr = fn(y: i64) -> i64 {
        return y + 3;
    };
    let part2: i64 = b(10);                # 13
    let part3: i64 = invoke(fn(z: i64) -> i64 {
        return z + 7;          # 12
    });
    return part1 + part2 + part3 + 4;      # 35+13+12+4 = 64
}
