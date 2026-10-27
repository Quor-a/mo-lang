# dbgtype —— 类型感知打印的被测程序
#
# 覆盖：结构体（含嵌套与 byte 字段）、数组、bool、byte、f64。
# 用于 tools/modtypetest.sh：验证 modb 的 p 命令按 DWARF 类型打印，
# 而不是一律当成 8 字节整数。
struct Inner {
    v: i64;
}

struct Outer {
    x: i64;
    y: i64;
    bv: byte;
    in: Inner;
}

fn main() -> i64 {
    let p1: Outer;
    let arr: [4] i64 = 0;
    let flag: bool = true;
    let bv: byte = 7;
    let fv: f64 = 1.5;
    let s: i64 = 0;
    p1.x = 3;
    p1.y = 4;
    p1.bv = 7;
    p1.in.v = 5;
    arr[0] = 10;
    arr[1] = 20;
    arr[2] = 30;
    arr[3] = 40;
    s = p1.x + p1.y + p1.in.v + arr[2];
    if flag { s = s + bv; }
    return s;
}
