
fn main() -> i64 {
    let a: [4] i64 = 0;
    let r: i64 = 0;
    let i: i64 = 7;
    # 正常路径不进 catch
    try {
        r = a[1];
    } catch(e) {
        r = 99;
    }
    if r != 0 { return 1; }
    # 嵌套：内层捕获
    try {
        try {
            r = a[i];
        } catch(e) {
            r = 10;
        }
    } catch(e) {
        r = 20;
    }
    if r != 10 { return 2; }
    # 外层捕获（内层无 try 直接抛）
    r = 0;
    try {
        r = a[i + 1];
    } catch(e) {
        r = 30 + e;
    }
    if r != 31 { return 3; }
    # 循环内的 try
    let s: i64 = 0;
    let k: i64 = 0;
    while k < 3 {
        try {
            s = s + a[k];
            if k == 1 { s = s + a[k * 8]; }
        } catch(e) {
            s = s + 7;
        }
        k = k + 1;
    }
    # 期望 s = 7（Python 模型：正常 0 + 内层捕获 10 + 外层 31 + 循环 7 的守卫都过才到这）
    if s != 7 { return 1; }
    return 0;
}
