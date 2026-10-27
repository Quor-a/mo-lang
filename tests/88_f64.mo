# 88 —— f64（浮点）
#
# 之前墨语言只有 i64：做不了科学计算、图形、音频。
#
# 设计要点：f64 值**不放在 xmm 寄存器里**，而是像整数一样在 rax 里传 ——
# 只不过 rax 里装的是 IEEE754 **位模式**，运算时才搬进 xmm 再搬回来。
# 代价是每步多两次 movq，换来的是不与整数通路互相污染。
import "assert.mo";

fn main() -> i64 {
    # ---- 算术（用 fint 看整数部分，避开浮点相等比较）----
    assert_eq("add", fint(1.5 + 2.25), 3);
    assert_eq("sub", fint(3.0 - 0.5), 2);
    assert_eq("mul", fint(1.5 * 4.0), 6);
    assert_eq("div", fint(3.0 / 2.0), 1);

    # ---- int 自动提升 ----
    assert_eq("int on right", fint(1.0 + 2), 3);
    assert_eq("int on left",  fint(2 + 1.5), 3);

    # ---- 取负：翻转符号位 ----
    assert_eq("neg", fint(0.0 - 2.5), fint(0.0 - 2.5));
    assert_eq("neg int part", fint(0.0 - (2.5)), -2);

    # ---- 比较（六项）----
    #
    # 🔴 这里最容易错：ucomisd 只设 ZF/PF/CF，**不设 SF/OF**，
    #    所以 setl/setg 无效，必须换成 setb/seta 族（见 f_cc）。
    assert_eq("lt",  to_i(1.5 < 2.5),  1);
    assert_eq("gt",  to_i(1.5 > 2.5),  0);
    assert_eq("le",  to_i(2.5 <= 2.5), 1);
    assert_eq("ge",  to_i(2.5 >= 2.5), 1);
    assert_eq("eq",  to_i(2.5 == 2.5), 1);
    assert_eq("ne",  to_i(2.5 != 2.5), 0);

    # ---- 负数比较：ucomisd 顺序反了的话这里会挂 ----
    assert_eq("neg lt", to_i((0.0 - 2.5) < 0.0), 1);
    assert_eq("neg gt", to_i((0.0 - 2.5) > 0.0), 0);

    # ---- 转换 ----
    assert_eq("i2f", fint(f64(7)), 7);
    assert_eq("f2i", fint(f64(3) * f64(3)), 9);

    # ---- 位模式：与 IEEE754 已知值核对 ----
    assert_eq("1.0 bits",   bits(1.0),   4607182418800017408);
    assert_eq("2.0 bits",   bits(2.0),   4611686018427387904);
    assert_eq("0.5 bits",   bits(0.5),   4602678819172646912);
    assert_eq("100.0 bits", bits(100.0), 4636737291354636288);

    return test_done();
}
