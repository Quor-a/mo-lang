# expect: 6
# v1.1153: enum 形参值语义修复 — enum_type_exists 只查简单 enum
# 常量表（O_ENAME），带数据 enum（Sh）查不到 → 被 v1.1110 前向
# struct 注册成引用语义，跨函数传参后值用全错。现在双表都查，
# enum 形参恢复 v1.1057 的 i64 值语义。
import "io.mo";

enum Sh { Circle(i64); Square(i64); }

fn bump(s: Sh) -> i64 {
    let v: i64 = 0;
    match s {
        Circle(x) => { v = x + 1; }
        Square(x) => { v = x + 2; }
    }
    return v;
}

fn main() -> i64 {
    let a = Sh.Circle(5);
    let b = Sh.Square(7);
    print_i64(bump(a));
    print_i64(bump(b));
    return 6;
}
