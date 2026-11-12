# cstd —— 对标 C 标准库的常用函数（用墨语言自己写的）
#
# 只做**有意义的子集**：
#   - 有墨语言特色的（不链接 libc，全部是 syscall）→ 保留
#   - 语言本身不支持的（浮点 printf %f、可变参数、locale）→ 不做，并注明
#
# 分组：
#   ctype   isalpha/isdigit/isalnum/isspace/isupper/islower/toupper/tolower
#   stdlib  abs/labs/abs64/min/max/swap/div/mod
#   string  strtol/strtoul/memmove/memchr/strncmp/strncpy/strrev/strdup
#   time    clock/gettimeofday/sleep/usleep
#   process atexit/abort/system
#   signal  signal/raise
#
# 没做的：printf 的浮点格式（%f/%e）、scanf 系列（要可变参数）、
#         setlocale、strtod/atof（语言没有浮点）、errno 的完整映射表。
import "str.mo";
import "io.mo";
import "err.mo";

# ---------------------------------------------------------------- ctype
#
# 注意：墨语言没有 char 字面量之外的字符类别表，所以直接判区间。
# 只用 ASCII —— 不做 locale，这也是 C 的 isalpha 在 "C" locale 下的行为。

fn is_alpha(c: i64) -> i64 {
    if c >= 65 { if c <= 90 { return 1; } }
    if c >= 97 { if c <= 122 { return 1; } }
    return 0;
}
fn is_upper(c: i64) -> i64 {
    if c >= 65 { if c <= 90 { return 1; } }
    return 0;
}
fn is_lower(c: i64) -> i64 {
    if c >= 97 { if c <= 122 { return 1; } }
    return 0;
}
fn is_alnum(c: i64) -> i64 {
    if is_alpha(c) == 1 { return 1; }
    if is_digit(c) == 1 { return 1; }
    return 0;
}
# 与 str.mo 的 is_space 不同：这个严格按 C 定义（空格 \t \n \v \f \r）
fn is_space_c(c: i64) -> i64 {
    if c == 32 { return 1; }
    if c == 9 { return 1; }
    if c == 10 { return 1; }
    if c == 11 { return 1; }
    if c == 12 { return 1; }
    if c == 13 { return 1; }
    return 0;
}
fn to_upper(c: i64) -> i64 {
    if is_lower(c) == 1 { return c - 32; }
    return c;
}
fn to_lower(c: i64) -> i64 {
    if is_upper(c) == 1 { return c + 32; }
    return c;
}

# ---------------------------------------------------------------- stdlib

fn abs(x: i64) -> i64 {
    if x < 0 { return 0 - x; }
    return x;
}
fn labs(x: i64) -> i64 { return abs(x); }
fn min_i64(a: i64, b: i64) -> i64 { if a < b { return a; } return b; }
fn max_i64(a: i64, b: i64) -> i64 { if a > b { return a; } return b; }

# div：商与余数。墨语言没有多返回值，余数放全局 C_REM。
var C_REM: i64 = 0;
fn cdiv(a: i64, b: i64) -> i64 {
    if b == 0 {
        err_set(E_ARG, "division by zero", "cdiv");
        C_REM = 0;
        return 0;
    }
    # 采用 C 语义（截断向零），与 Python 的向下取整不同 ——
    # 对标 C 就该用 C 的取整方向。
    let q: i64 = a / b;
    C_REM = a - q * b;
    return q;
}

# ---------------------------------------------------------------- string

# strtol：解析十进制整数，支持可选正负号与 0x 前缀。
# 不设置 endptr（墨语言没有二级指针）；解析失败返回 0 并置 err。
fn strtol(s: ptr) -> i64 {
    let i: i64 = 0;
    while is_space_c(load8(s + i)) == 1 { i = i + 1; }
    let neg: i64 = 0;
    if load8(s + i) == 45 { neg = 1; i = i + 1; }
    else { if load8(s + i) == 43 { i = i + 1; } }
    let base: i64 = 10;
    if load8(s + i) == 48 {
        if load8(s + i + 1) == 120 { base = 16; i = i + 2; }
        if load8(s + i + 1) == 88 { base = 16; i = i + 2; }
    }
    if is_alnum(load8(s + i)) == 0 {
        err_set(E_FORMAT, "strtol: no digits found", "strtol");
        return 0;
    }
    let v: i64 = 0;
    while 1 {
        let c: i64 = load8(s + i);
        let d: i64 = 0 - 1;
        if c >= 48 { if c <= 57 { d = c - 48; } }
        if base == 16 {
            if d < 0 {
                c = to_upper(c);
                if c >= 65 { if c <= 70 { d = c - 55; } }
            }
        }
        if d < 0 { break; }
        if d >= base { break; }
        v = v * base + d;
        i = i + 1;
    }
    if neg == 1 { return 0 - v; }
    return v;
}

# memmove：与 memcpy 不同，**必须**正确处理重叠。
# 源地址在前就从前往后拷，在后就从后往前拷 ——
# 少了这个判断，重叠时会把还没读的数据覆盖掉。
fn memmove(dst: i64, src: i64, n: i64) -> i64 {
    if dst == src { return 0; }
    if n <= 0 { return 0; }
    if dst < src {
        let i: i64 = 0;
        while i < n {
            store8(dst + i, load8(src + i));
            i = i + 1;
        }
        return 0;
    }
    let j: i64 = n - 1;
    while j >= 0 {
        store8(dst + j, load8(src + j));
        j = j - 1;
    }
    return 0;
}

fn memchr(p: i64, c: i64, n: i64) -> i64 {
    let i: i64 = 0;
    while i < n {
        if load8(p + i) == c { return p + i; }
        i = i + 1;
    }
    return 0;
}

fn strncmp(a: ptr, b: ptr, n: i64) -> i64 {
    let i: i64 = 0;
    while i < n {
        let x: i64 = load8(a + i);
        let y: i64 = load8(b + i);
        if x != y { return x - y; }
        if x == 0 { return 0; }
        i = i + 1;
    }
    return 0;
}

fn strncpy(dst: ptr, src: ptr, n: i64) -> i64 {
    let i: i64 = 0;
    while i < n {
        let c: i64 = load8(src + i);
        store8(dst + i, c);
        if c == 0 { break; }
        i = i + 1;
    }
    # 与 C 一致：不足 n 的部分补 0
    while i < n {
        store8(dst + i, 0);
        i = i + 1;
    }
    return 0;
}

fn strrev(s: ptr) -> i64 {
    let n: i64 = strlen(s);
    let i: i64 = 0;
    let j: i64 = n - 1;
    while i < j {
        let t: i64 = load8(s + i);
        store8(s + i, load8(s + j));
        store8(s + j, t);
        i = i + 1;
        j = j - 1;
    }
    return 0;
}

# ---------------------------------------------------------------- time

# 毫秒级单调时钟：clock_gettime(CLOCK_MONOTONIC=1)
#
# 🔴 v1.126：缓冲必须是**一个数组**，不能是两个独立全局。
#    clock_gettime 一次写 16 字节（sec + nsec），而墨语言里两个独立全局
#    在内存中**并不相邻** —— 实测：声明 `var A; var B;` 后对 &A 做
#    clock_gettime，B 恒为 0，紧跟其前后的其它全局也都未被改写，
#    说明 nsec 落在了两者之间的空隙里（全局按 16 字节槽排布）。
#
#    后果（本缺陷的全部危险之处）：TS_NSEC 恒为 0，clock_ms() 于是
#    **静默退化成 1 秒分辨率** —— 不报错、不崩溃，返回值看着完全正常，
#    只是所有毫秒级测量都变成整秒跳变。lib/timer.mo 的时间轮就是被它
#    坑到：定时器线程每次只睡 16ms 却不推进，攒够 1 秒才一次性补
#    62 个 tick，于是 50ms 的定时器实测要等 ~1 秒。
#
#    判据（已写进 tools/timertest.sh）：间隔 50ms 的两次 clock_ms()
#    差值必须是 ~50，而不是 0 或 1000。
var CTS: [2] i64 = 0;

fn clock_ms() -> i64 {
    syscall(228, 1, &CTS, 0, 0, 0, 0);
    return CTS[0] * 1000 + CTS[1] / 1000000;
}

# 墙上时间（秒，Unix 纪元）
var VTS: [2] i64 = 0;
fn time_secs() -> i64 {
    syscall(96, &VTS, 0, 0, 0, 0, 0);
    return VTS[0];
}

# 🔴 v1.126：sleep_ms 此前**完全没有设置 timespec**，直接拿 clock_ms
#    写脏的 TS_SEC/TS_NSEC 当 {sec,nsec} 传给 nanosleep(35) ——
#    而 nsec 从来没被写过（恒 0），且秒数是上一次读时钟的残留值。
#    于是 sleep_ms(任意值) 的实际行为取决于上一次 clock_ms 的残留。
var STS: [2] i64 = 0;
fn sleep_ms(ms: i64) -> i64 {
    STS[0] = ms / 1000;
    STS[1] = ms - STS[0] * 1000;
    STS[1] = STS[1] * 1000000;
    syscall(35, &STS, 0, 0, 0, 0, 0);
    return 0;
}

# ---------------------------------------------------------------- process

fn abort() -> i64 {
    syscall(1, 2, "abort\n", 6, 0, 0, 0);
    syscall(60, 134, 0, 0, 0, 0, 0);
    return 0;
}

fn exit(code: i64) -> i64 {
    syscall(60, code, 0, 0, 0, 0, 0);
    return 0;
}

# ---------------------------------------------------------------- signal

# signal(sig, handler) —— handler 传函数地址。
# 墨语言目前**没有函数指针类型**，所以只能传 0(SIG_DFL) 或 1(SIG_IGN)。
# 注册真正的自定义处理函数要等语言支持函数指针，这里如实标注限制。
fn signal(sig: i64, handler: i64) -> i64 {
        # asm-generic 的 rt_sigaction 多一个 sigsetsize 实参（x86 只要 3 个），
    # 缺了内核返回 -EINVAL —— 补 sizeof(sigset_t)=8。
    return syscall(13, sig, handler, 0, 8);
}

fn raise(sig: i64) -> i64 {
    # kill(getpid(), sig)：getpid=39, kill=62
    let pid: i64 = syscall(39, 0, 0, 0, 0, 0, 0);
    return syscall(62, pid, sig, 0, 0, 0, 0);
}
