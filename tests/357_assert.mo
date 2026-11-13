# 357: assert(cond, msg) 内建 —— 为假时写 stderr + 走 panic 路径（catch e=2）。
fn expect2(e: i64) -> i64 {
    if e == 2 { return 1; }
    return 0;
}
fn main() -> i64 {
    let x: i64 = 5;
    assert(x == 5, "must pass");
    if x > 0 {
        assert(x < 10, "range pass");
    }
    let n: i64 = 0;
    try {
        assert(x == 3, "assert fired\n");
        n = 1;
    } catch(e) {
        n = expect2(e);
    }
    if n != 1 { return 1; }
    return 0;
}
