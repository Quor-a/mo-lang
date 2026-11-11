# expect: 136
# v1.1158: const fn 循环支持（let 局部变量 + 赋值 + while，可嵌套/可调 const fn）
import "io.mo";

# 1) 累加 1..n：sum_to(10) = 55
const fn sum_to(n: i64) -> i64 {
    let s: i64 = 0;
    let i: i64 = 1;
    while i <= n { s = s + i; i = i + 1; }
    return s;
}

# 2) 阶乘：fact(5) = 120
const fn fact(n: i64) -> i64 {
    let r: i64 = 1;
    let i: i64 = 2;
    while i <= n { r = r * i; i = i + 1; }
    return r;
}

# 3) 迭代 fib：ifib(10) = 55
const fn ifib(n: i64) -> i64 {
    let a: i64 = 0;
    let b: i64 = 1;
    let t: i64 = 0;
    let i: i64 = 0;
    while i < n { t = a + b; a = b; b = t; i = i + 1; }
    return a;
}

# 4) 循环 + if：count_odd(9) = 5
const fn count_odd(n: i64) -> i64 {
    let c: i64 = 0;
    let i: i64 = 1;
    while i <= n {
        if i % 2 == 1 { c = c + 1; }
        i = i + 1;
    }
    return c;
}

# 5) 循环内调用 const fn：sum_sq(5) = 1+4+9+16+25 = 55
const fn sq(x: i64) -> i64 { return x * x; }
const fn sum_sq(n: i64) -> i64 {
    let s: i64 = 0;
    let i: i64 = 1;
    while i <= n { s = s + sq(i); i = i + 1; }
    return s;
}

# 6) 欧几里得：gcd(48,18) = 6
const fn gcd(a: i64, b: i64) -> i64 {
    let x: i64 = a;
    let y: i64 = b;
    let t: i64 = 0;
    while y != 0 { t = x % y; x = y; y = t; }
    return x;
}

# 7) 嵌套循环：tri(4) = 1+3+6+10 = 20
const fn tri(n: i64) -> i64 {
    let s: i64 = 0;
    let i: i64 = 1;
    while i <= n {
        let j: i64 = 1;
        while j <= i { s = s + j; j = j + 1; }
        i = i + 1;
    }
    return s;
}

# 8) 循环内 return：first_over(20) = 5（5*5=25 > 20）
const fn first_over(n: i64) -> i64 {
    let i: i64 = 1;
    while i < 100 {
        if i * i > n { return i; }
        i = i + 1;
    }
    return 0 - 1;
}

# 9) 复合赋值：cacc(6) = 21
const fn cacc(n: i64) -> i64 {
    let s: i64 = 0;
    let i: i64 = 1;
    while i <= n { s += i; i += 1; }
    return s;
}

fn main() -> i64 {
    # 独立场景加权求和，避免相互掩盖：1160 % 256 = 136
    let total: i64 = 0;
    total = total + sum_to(10) * 1;
    total = total + fact(5) * 2;
    total = total + ifib(10) * 3;
    total = total + count_odd(9) * 4;
    total = total + sum_sq(5) * 5;
    total = total + gcd(48, 18) * 6;
    total = total + tri(4) * 7;
    total = total + first_over(20) * 8;
    total = total + cacc(6) * 9;
    return total;
}
