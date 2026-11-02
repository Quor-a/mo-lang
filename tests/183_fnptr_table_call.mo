# expect: 16
# 测试：数组元素函数指针直接调用 t[0](x)（v1.1020）
# push f → 实参 push → 逆序弹寄存器 → pop rax=f → call rax
fn inc(n: i64) -> i64 { return n + 1; }
fn dbl(n: i64) -> i64 { return n * 2; }

fn main() -> i64 {
    let tbl: [2] ptr = [&inc, &dbl];
    return tbl[0](5) + tbl[1](5);
}
