import "io.mo";
# 362: 恒等消除 + 强度削减（v1.1182）
fn f(n: i64) -> i64 {
    let s: i64 = 0;
    s = s + (n + 0);        # 7
    s = s + (n * 8);        # 56
    s = s + (n * 1);        # 7
    s = s + (n * 0);        # 0
    s = s + (n << 0);       # 7
    s = s + (n >> 0);       # 7
    s = s + (n | 0);        # 7
    s = s + (n & -1);       # 7
    s = s + (n ^ 0);        # 7
    s = s + (n - 0);        # 7
    s = s + (n * 1024);     # 7168（大 2^k → shl）
    return s;               # 7*9 + 56 + 7168 = 7295
}
fn main() -> i64 {
    print_i64(f(7)); print_nl();
    if f(7) != 7280 { return 1; }
    if f(0) != 0 { return 2; }
    if f(-3) != 0 - 3120 { return 3; }   # 7*9=-63? 逐项: -3*9=-27-24+...= -27+(-24)+(-21*2)+(-3*1024)
    print_i64(f(7)); print_nl();
    return 0;
}
