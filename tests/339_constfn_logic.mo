# expect: 168
# v1.1160: const fn 逻辑运算符 && || 与短路求值
import "io.mo";

# 1) 区间判断：inr(5,1,10) = 1
const fn inr(x: i64, lo: i64, hi: i64) -> i64 {
    if x >= lo && x <= hi { return 1; }
    return 0;
}

# 2) 任一为零：ez(7,8) = 0
const fn ez(a: i64, b: i64) -> i64 {
    if a == 0 || b == 0 { return 1; }
    return 0;
}

# 3) 双正相乘：po(3,4) = 12
const fn po(a: i64, b: i64) -> i64 {
    if a > 0 && b > 0 { return a * b; }
    return 0 - 1;
}

# 4) 短路保护除数：sd(10,0) = 255（-1），不得除零
const fn sd(a: i64, b: i64) -> i64 {
    if b != 0 && a / b > 1 { return a / b; }
    return 0 - 1;
}

# 5) 三值或：tri(0,0,5) = 1
const fn tri(a: i64, b: i64, c: i64) -> i64 {
    if a > 0 && b > 0 || c > 0 { return 1; }
    return 0;
}

# 6) 同号：sgn2(0-2, 0-3) = 1
const fn sgn2(a: i64, b: i64) -> i64 {
    if (a > 0 && b > 0) || (a < 0 && b < 0) { return 1; }
    return 0;
}

# 7) while 条件含 &&：wh(100) = 0+1+2+3+4 = 10
const fn wh(n: i64) -> i64 {
    let i: i64 = 0;
    let s: i64 = 0;
    while i < n && i < 5 { s += i; i += 1; }
    return s;
}

# 8) 循环里 && 计数（1..20 中能被 6 整除的个数）：cn(20) = 3
const fn cn(n: i64) -> i64 {
    let i: i64 = 1;
    let c: i64 = 0;
    while i <= n {
        if i % 2 == 0 && i % 3 == 0 { c += 1; }
        i += 1;
    }
    return c;
}

# 9) 或短路：sl(0,5) = 0
const fn sl(a: i64, b: i64) -> i64 {
    if a > b || a == 0 { return a; }
    return b;
}

# 10) 分解质因数个数（含 continue 与 ||）：np(12) = 3
const fn np(n: i64) -> i64 {
    let x: i64 = n;
    let c: i64 = 0;
    let p: i64 = 2;
    while x > 1 {
        if x % p == 0 { x = x / p; c += 1; continue; }
        if p == 2 { p = 3; continue; }
        p += 2;
    }
    return c;
}

fn main() -> i64 {
    let total: i64 = 0;
    total = total + inr(5, 1, 10) * 1;
    total = total + ez(7, 8) * 2;
    total = total + po(3, 4) * 3;
    total = total + sd(10, 0) * 4;
    total = total + tri(0, 0, 5) * 5;
    total = total + sgn2(0 - 2, 0 - 3) * 6;
    total = total + wh(100) * 7;
    total = total + cn(20) * 8;
    total = total + sl(0, 5) * 9;
    total = total + np(12) * 10;
    return total;
}
