# 120 —— 嵌套结构体的布局（1.105）
#
# 修复前有两个独立的布局缺陷，都**不报错、不崩溃**，只是静默写坏：
#
#  ① 字段偏移按 `fi * 8` 算，等价于"每个字段都占 1 个槽"。
#     struct W { inner: P; b: i64; }   （P 有两个字段）
#       inner @0 占 2 个槽，b 应在 @16，实际被算成 @8 = inner.y 的槽
#     => w.b = 3 覆盖 w.inner.y，读回来 1 / 3 / 3（正确是 1 / 2 / 3）。
#
#  ② 结构体占多少槽用 st_nfields（只数**直接**字段）。
#     struct W 被算成 2 槽（实为 3），于是局部变量/全局变量在数据段
#     只留 2 个 qword，末尾字段写到相邻数据上 ——
#     实测把字符串字面量的首字节写成 3，于是 print("after\n") 输出变空。
#
# 修法：ty_size 用 st_words（递归展开），字段偏移用 st_field_off（累计），
#       槽分配与整体拷贝的词数也一并改成 st_words。
#
# ⚠️ 覆盖：seed 与 compiler.mo 都不用 struct，这条路径**不在**自举验证范围内。
#
# ⚠️ 已知未修：局部（栈上）结构体数组写最后一个元素的最后一个字段会 SIGSEGV
#    （`let a: [3] W; a[2].b = 9;`）。元素大小 > 16 字节时才会触发，
#    [3] P（16 字节）与 i64 数组都不受影响。本测试刻意避开该场景。
import "assert.mo";

struct P {
    x: i64;
    y: i64;
}

# 嵌套字段在**前**，后面还有字段 —— 这是触发错位的关键布局
struct W {
    inner: P;
    b: i64;
}

# 嵌套字段在**中间**
struct W2 {
    a: i64;
    inner: P;
    b: i64;
}

# 三层嵌套
struct T {
    a: i64;
    mid: W;
    c: i64;
}

var GW: W;
# 声明在 GW 之后：GW 若少分配槽就会写到这里
var GS: [16] byte = "abcdefghijklmno";

fn main() -> i64 {
    print("=== 嵌套结构体布局 ===\n");

    # ---- 1) 局部：嵌套字段在前，后面还有字段 ----
    let w: W;
    w.inner.x = 1;
    w.inner.y = 2;
    w.b = 3;
    assert_eq("局部 inner.x", w.inner.x, 1);
    assert_eq("局部 inner.y", w.inner.y, 2);
    assert_eq("局部 b", w.b, 3);
    assert_eq("局部求和", w.inner.x + w.inner.y + w.b, 6);

    # ---- 2) 嵌套字段在中间 ----
    let m: W2;
    m.a = 4;
    m.inner.x = 5;
    m.inner.y = 6;
    m.b = 7;
    assert_eq("中段 a", m.a, 4);
    assert_eq("中段 inner.x", m.inner.x, 5);
    assert_eq("中段 inner.y", m.inner.y, 6);
    assert_eq("中段 b", m.b, 7);

    # ---- 3) 三层嵌套 ----
    let t: T;
    t.a = 1;
    t.mid.inner.x = 2;
    t.mid.inner.y = 3;
    t.mid.b = 4;
    t.c = 5;
    assert_eq("三层 a", t.a, 1);
    assert_eq("三层 mid.inner.x", t.mid.inner.x, 2);
    assert_eq("三层 mid.inner.y", t.mid.inner.y, 3);
    assert_eq("三层 mid.b", t.mid.b, 4);
    assert_eq("三层 c", t.c, 5);
    assert_eq("三层求和", t.a + t.mid.inner.x + t.mid.inner.y + t.mid.b + t.c, 15);

    # ---- 4) 全局：末尾字段不得写到相邻数据上 ----
    GW.inner.x = 6;
    GW.inner.y = 7;
    GW.b = 8;
    assert_eq("全局 inner.x", GW.inner.x, 6);
    assert_eq("全局 inner.y", GW.inner.y, 7);
    assert_eq("全局 b", GW.b, 8);

    # ---- 5) 相邻数据未被覆盖（GS 的长度与首字节）----
    assert_eq("相邻 byte 数组首字节", GS[0], 97);
    assert_eq("相邻 byte 数组末字节", GS[14], 111);

    # ---- 6) 字符串字面量未被覆盖 ----
    #  修复前：局部 W 少分配 1 槽，w.b 写到 "lit" 的首字节上，
    #  于是 print 输出变空。这里用字面量长度间接确认它没被写坏。
    let sl: i64 = slen("lit");
    assert_eq("字面量长度未被破坏", sl, 3);

    # ---- 7) 嵌套字段整体赋给同类型变量（拷贝词数必须是 st_words）----
    let q: P = w.inner;
    assert_eq("整体拷贝 q.x", q.x, 1);
    assert_eq("整体拷贝 q.y", q.y, 2);

    # ---- 8) 结构体变量整体赋值 ----
    let r: W;
    r = w;
    assert_eq("整体赋值 r.inner.x", r.inner.x, 1);
    assert_eq("整体赋值 r.inner.y", r.inner.y, 2);
    assert_eq("整体赋值 r.b", r.b, 3);

    # ---- 9) 结构体数组（刻意避开已知的栈上越界场景：只写到 a[1]）----
    let arr: [3] W;
    arr[0].inner.x = 1;
    arr[0].inner.y = 2;
    arr[0].b = 3;
    arr[1].inner.x = 4;
    arr[1].inner.y = 5;
    arr[1].b = 6;
    assert_eq("数组 a[0].inner.x", arr[0].inner.x, 1);
    assert_eq("数组 a[0].b", arr[0].b, 3);
    assert_eq("数组 a[1].inner.x", arr[1].inner.x, 4);
    assert_eq("数组 a[1].inner.y", arr[1].inner.y, 5);
    assert_eq("数组 a[1].b", arr[1].b, 6);

    return test_done();
}

fn slen(s: i64) -> i64 {
    let n: i64 = 0;
    let i: i64 = 0;
    while i < 64 {
        if load8(s + i) == 0 { return n; }
        n = n + 1;
        i = i + 1;
    }
    return n;
}
