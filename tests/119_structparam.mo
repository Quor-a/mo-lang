# 119 —— 结构体作为实参（1.104）
#
# 修复前：`work(a)` 编译正常、运行**段错误**（退出码 139），
# 而显式写 `work(&a)` 却是对的。
#
# 根因：结构体变量/元素在表达式里被加载成**第一个字段的值**，
# 而形参 `o: S` 是 ptr(S) 语义（类名形参 = this 指针）。
# 于是函数里 `o.x` 去读 [3] —— 地址 3 不可访问。
#
# 修法：结构体变量（load_sym）与结构体数组元素（下标表达式）
# 在表达式里都退化成**地址**，与数组名一致。
#
# ⚠️ 语义：这是**引用**语义，不是 C 的按值拷贝。
#    mut() 里改 o.x 会写回 a.x —— 与 ptr 形参一致，测试里固化下来。
#
# ⚠️ 覆盖：seed 与 compiler.mo 都不用 struct，所以这条路径**不在**
#    自举验证范围内，只能靠本文件兜底。
import "assert.mo";

struct P {
    x: i64;
    y: i64;
}

struct W {
    a: i64;
    inner: P;
}

var G: P;

fn sum(o: P) -> i64 {
    return o.x + o.y;
}

fn two(o: P, k: i64) -> i64 {
    return o.x * k + o.y;
}

fn outer(w: W) -> i64 {
    return w.a + w.inner.x + w.inner.y;
}

fn mut(o: P) -> i64 {
    o.x = 100;
    return 0;
}

fn main() -> i64 {
    print("=== 结构体作为实参 ===\n");

    # ---- 1) 局部结构体变量 ----
    let a: P;
    a.x = 3;
    a.y = 4;
    assert_eq("sum(局部结构体)", sum(a), 7);

    # ---- 2) 全局结构体变量（走 movabs 分支）----
    G.x = 10;
    G.y = 20;
    assert_eq("sum(全局结构体)", sum(G), 30);

    # ---- 3) 结构体与其他参数混合 ----
    assert_eq("two(结构体, i64)", two(a, 10), 34);

    # ---- 4) 嵌套结构体 ----
    let w: W;
    w.a = 1;
    w.inner.x = 2;
    w.inner.y = 3;
    assert_eq("outer(嵌套结构体)", outer(w), 6);

    # ---- 5) 结构体数组元素 ----
    let arr: [4] P;
    arr[0].x = 5;
    arr[0].y = 6;
    arr[1].x = 50;
    arr[1].y = 60;
    assert_eq("sum(arr[0])", sum(arr[0]), 11);
    assert_eq("sum(arr[1])", sum(arr[1]), 110);

    # ---- 6) 引用语义：形参里改字段会写回实参 ----
    let r: i64 = mut(a);
    assert_eq("引用语义: 形参改字段写回", a.x, 100);
    assert_eq("引用语义: 改后求和", sum(a), 104);

    # ---- 7) 回归：字段读取与显式取地址不受影响 ----
    let b: P;
    b.x = 7;
    b.y = 8;
    assert_eq("回归: 字段读 x", b.x, 7);
    assert_eq("回归: 字段读 y", b.y, 8);
    assert_eq("回归: 显式取地址", sum(&b), 15);

    return test_done();
}
