# expect: 127
# v1.1159: const fn 循环控制（break / continue，可嵌套、可跨 if 分支）
import "io.mo";

# 1) 找到最小约数后 break：fd(35) = 5
const fn fd(n: i64) -> i64 {
    let i: i64 = 2;
    let r: i64 = 0 - 1;
    while i < n {
        if n % i == 0 { r = i; break; }
        i = i + 1;
    }
    return r;
}

# 2) continue 跳过偶数：sum_odd(6) = 1+3+5 = 9
const fn sum_odd(n: i64) -> i64 {
    let s: i64 = 0;
    let i: i64 = 1;
    while i <= n {
        if i % 2 == 0 { i += 1; continue; }
        s += i;
        i += 1;
    }
    return s;
}

# 3) 内层 break 不影响外层：nested_brk(3) = 1+2+3 = 6 ... 见注释
const fn nested_brk(n: i64) -> i64 {
    let i: i64 = 1;
    let acc: i64 = 0;
    while i <= n {
        let j: i64 = 1;
        while j <= 10 {
            if j > i { break; }
            acc += j;
            j += 1;
        }
        i += 1;
    }
    return acc;
}

# 4) 累加越界即 break：first_over(10, 12) = 5
const fn first_over(n: i64, lim: i64) -> i64 {
    let i: i64 = 1;
    let s: i64 = 0;
    let r: i64 = 0 - 1;
    while i <= n {
        s += i;
        if s > lim { r = i; break; }
        i += 1;
    }
    return r;
}

# 5) continue 跳过 3 的倍数：cnt(10) = 7
const fn cnt(n: i64) -> i64 {
    let i: i64 = 0;
    let c: i64 = 0;
    while i < n {
        i += 1;
        if i % 3 == 0 { continue; }
        c += 1;
    }
    return c;
}

# 6) break 位于 if/else 的 else 分支：felse(9) = 3+30-... 见 main
const fn felse(n: i64) -> i64 {
    let i: i64 = 0;
    let t: i64 = 0;
    while i < n {
        if i < 3 { t += 1; }
        else { if i == 5 { break; } else { t += 10; } }
        i += 1;
    }
    return t;
}

# 7) 两处 continue：fcont(6) = 1+9+25+36 = 71
const fn fcont(n: i64) -> i64 {
    let i: i64 = 1;
    let s: i64 = 0;
    while i <= n {
        if i == 2 { i += 1; continue; }
        if i == 4 { i += 1; continue; }
        s += i * i;
        i += 1;
    }
    return s;
}

# 8) 循环中调用含 break 的 const fn：各次调用的 break 互不干扰
const fn loop_call(n: i64) -> i64 {
    let i: i64 = 4;
    let s: i64 = 0;
    while i <= n { s += fd(i); i += 1; }
    return s;
}

# 9) break 前有复合赋值：ceil_sq(50) = 8
const fn ceil_sq(n: i64) -> i64 {
    let i: i64 = 1;
    while i < 1000 {
        if i * i >= n { break; }
        i += 1;
    }
    return i;
}

fn main() -> i64 {
    let total: i64 = 0;
    total = total + fd(35) * 1;
    total = total + sum_odd(6) * 2;
    total = total + nested_brk(3) * 3;
    total = total + first_over(10, 12) * 4;
    total = total + cnt(10) * 5;
    total = total + felse(9) * 6;
    total = total + fcont(6) * 7;
    total = total + loop_call(12) * 8;
    total = total + ceil_sq(50) * 9;
    return total;
}
