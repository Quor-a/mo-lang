
fn main() -> i64 {
    let a: [4] i64 = 0;
    let r: i64 = 0;
    let i: i64 = 9;
    try {
        r = a[i];
    } catch(e) {
        r = e;
    }
    if r != 1 { return 1; }
    try {
        panic("custom failure\n");
        r = 100;
    } catch(e) {
        r = e * 10;
    }
    if r != 20 { return 2; }
    # 嵌套：内层 panic 被内层 catch
    try {
        try {
            panic("inner\n");
        } catch(e) {
            r = e + 1;
        }
    } catch(e) {
        r = 99;
    }
    if r != 3 { return 3; }
    return 0;
}
