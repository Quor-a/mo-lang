import "io.mo";
# 360: 局部常量传播（v1.1180）
fn main() -> i64 {
    let a: i64 = 10;
    let b: i64 = a + 5;        # 15
    if b != 15 { return 1; }
    let c: i64 = b * 2;        # 30
    if c != 30 { return 2; }
    let d: i64 = 7;
    d = d + 1;                 # 失效点：赋值
    if d != 8 { return 3; }
    let e: i64 = 3;
    let p: i64 = &e as i64;    # 失效点：取址
    if e != 3 { return 4; }
    if 1 == 1 {
        let m: i64 = a + 1;    # 11（跨块读常量）
        if m != 11 { return 5; }
    }
    let q: i64 = 50;
    q = q + a;                 # 60
    if q != 60 { return 6; }
    let arr: [3] i64 = [1,2,3];
    arr[1] = a;
    if arr[1] != 10 { return 7; }
    let s: i64 = 0;
    let i: i64 = 0;
    while i < 3 {
        s = s + a;             # 循环内失效
        i = i + 1;
    }
    if s != 30 { return 8; }
    let cb = fn() -> i64 {
        let z: i64 = 9;
        return z * 2;          # 18
    };
    if cb() != 18 { return 9; }
    print_i64(c); print_nl();
    return 0;
}
