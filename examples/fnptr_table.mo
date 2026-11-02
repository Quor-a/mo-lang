# 函数指针表示例（分派表）
fn inc(x: i64) -> i64 { return x + 1; }
fn dbl(x: i64) -> i64 { return x * 2; }

fn main() -> i64 {
    let tbl: [2] ptr = [&inc, &dbl];
    return tbl[0](10) + tbl[1](10);   # 11 + 20 = 31
}
