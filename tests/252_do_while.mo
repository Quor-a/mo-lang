# expect: 111
# do { ... } while (cond);（v1.1071）：body 先行、continue→cond、break→end、嵌套。
fn main() -> i64 {
    let i: i64 = 0;
    let s: i64 = 0;
    do {
        i = i + 1;
        if i == 2 { continue; }    # 跳过 2
        s = s + i * 10;            # 10+30+40 = 80
    } while (i < 4);
    let j: i64 = 0;
    do {
        j = j + 1;
        if j == 3 { break; }
    } while (1);                   # j = 3
    let k: i64 = 0;
    do {
        s = s + 1;                 # 只跑一次: s=81
        k = k + 1;
    } while (k < 0);
    return s + j * 10;             # 81 + 30 = 111
}
