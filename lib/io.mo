import "str.mo";

fn print(s: i64) -> i64 {
    syscall(1, 1, s, strlen(s), 0, 0, 0);
    return 0;
}

fn print_i64(v: i64) -> i64 {
    let buf: [24] i64 = 0;
    let i: i64 = 22;
    let neg: i64 = 0;
    if v < 0 {
        neg = 1;
        v = 0 - v;
    }
    if v == 0 {
        store8(&buf, 48);
        syscall(1, 1, &buf, 1, 0, 0, 0);
        return 0;
    }
    while v > 0 {
        store8(&buf + i, 48 + (v % 10));
        v = v / 10;
        i = i - 1;
    }
    if neg == 1 {
        store8(&buf + i, 45);
        i = i - 1;
    }
    syscall(1, 1, &buf + i + 1, 22 - i, 0, 0, 0);
    return 0;
}

fn print_nl() -> i64 {
    print("\n");
    return 0;
}

# 把无符号数按 base 进制写入 buf，返回字符串长度（不输出）
fn utoa(v: i64, buf: i64, base: i64) -> i64 {
    let tmp: [24] i64 = 0;
    let n: i64 = 0;
    let neg: i64 = 0;
    # 负数：先输出 '-' 再按绝对值转换。
    # 原来直接 while v > 0，负数一律走空循环，结果输出空串。
    if v < 0 {
        neg = 1;
        store8(buf, 45);
        v = 0 - v;
    }
    if v == 0 {
        store8(buf + neg, 48);
        store8(buf + neg + 1, 0);
        return neg + 1;
    }
    while v > 0 {
        let d: i64 = v % base;
        if d < 10 {
            store8(&tmp + n, 48 + d);
        } else {
            store8(&tmp + n, 87 + d);
        }
        v = v / base;
        n = n + 1;
    }
    let i: i64 = 0;
    while i < n {
        store8(buf + neg + i, load8(&tmp + (n - 1 - i)));
        i = i + 1;
    }
    store8(buf + neg + n, 0);
    return neg + n;
}

fn print_hex(v: i64) -> i64 {
    let buf: [24] i64 = 0;
    utoa(v, &buf, 16);
    print(&buf);
    return 0;
}

# ==========================================================================
#  f64 输出
# ==========================================================================
# f64 的打印完全靠**运行时**的 SSE 指令 + 整数格式化拼出来 ——
# 编译器自身没有浮点（它只用 i64）。
#
# 做法：整数部分 cvttsd2si 截断后 print_i64；小数部分反复 ×10 取整。
# 固定 6 位。不是最快的做法，但**不依赖 libc**且行为可预测。

# 打印 f64（参数声明为 f64，于是下面的 - 与 * 自动走 SSE）
fn print_f64(v: f64) -> i64 {
    if v < 0.0 {
        print("-");
        v = 0.0 - v;
    }
    # 四舍五入而非截断：先加半个最低位。
    # 少了这一步，3.14159 会打成 3.141589（其 double 实为
    # 3.1415899999...），与 printf("%.6f") 的 3.141590 差 1。
    v = v + 0.0000005;
    let ip: i64 = fint(v);
    print_i64(ip);
    print(".");
    let fr: f64 = v - f64(ip);
    let i: i64 = 0;
    while i < 6 {
        fr = fr * 10.0;
        let d: i64 = fint(fr);
        print_i64(d);
        fr = fr - f64(d);
        i = i + 1;
    }
    return 0;
}
