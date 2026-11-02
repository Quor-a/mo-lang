# expect: 12
# for 的 init 支持裸赋值 i = 0 / i += 1（v1.1072），并修复 v1.1070
# for-in 引入时误删的括号形式 '(' 消费（t132 回归）。
fn main() -> i64 {
    let s: i64 = 0;
    for (let k: i64 = 0; k < 3; k++) {
        let i: i64 = 9;
        for (i = 0; i < 4; i++) { s = s + 1; }
    }
    return s;
}
