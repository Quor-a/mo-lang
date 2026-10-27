# expect: 0
# 栈上结构体数组：最后一个元素的**最后一个字段**曾经写到数组之外。
#
# 栈槽约定：变量 off 是最低字节，占 [off, off+size-1]（向上增长），
# 上一个变量占 [p+8, ...]。所以数组顶端最高只能到 p+7，
# off 必须是 p + 8 - esz*n。原来写成 p - esz*(n-1)，只在 esz==8 时正确。
#
# esz>8 时数组整体上移 esz-8 字节：
#   - 数组是第一个局部变量 → 越界部分正好是保存的 rbp 与**返回地址**
#     → `a[2].b = 9` 改掉返回地址，函数返回时 SIGSEGV（退出码 139）
#   - 数组前面还有别的局部变量 → 越界部分写进那个变量，静默篡改
# 两者都不报编译错误，所以必须由测试钉死。
import "io.mo";

struct Inner { x: i64; y: i64; }
struct W { inner: Inner; b: i64; }

var FAILS: i64 = 0;

fn ck(got: i64, want: i64, tag: i64) -> i64 {
    if got != want {
        print("FAIL "); print_i64(tag); print(": got ");
        print_i64(got); print(" want "); print_i64(want); print("\n");
        FAILS = FAILS + 1;
    }
    return 0;
}

# 场景一：数组是第一个局部变量，写最后一个元素的最后一个字段。
# 修复前这里直接改掉返回地址 → SIGSEGV，根本走不到下面的断言。
fn t_first_local() -> i64 {
    let a: [3] W;
    a[0].inner.x = 1;
    a[1].inner.y = 2;
    a[2].b = 33;
    ck(a[0].inner.x, 1, 101);
    ck(a[1].inner.y, 2, 102);
    ck(a[2].b, 33, 103);
    return 0;
}

# 场景二：数组前面还有局部变量。修复前 a[2].inner.y 会写进 m0 的槽，
# 于是 m0 从 111 变成 33 —— 不崩溃、不报错，只是值悄悄错了。
fn t_prev_local() -> i64 {
    let m0: i64 = 111;
    let a: [3] W;
    let m1: i64 = 222;
    a[2].inner.y = 33;
    ck(m0, 111, 201);
    ck(m1, 222, 202);
    ck(a[2].inner.y, 33, 203);
    return 0;
}

# 场景三：元素之间不得重叠 —— 逐个写满再逐个读回。
fn t_no_overlap() -> i64 {
    let a: [4] W;
    let i: i64 = 0;
    while i < 4 {
        a[i].inner.x = 100 + i;
        a[i].inner.y = 200 + i;
        a[i].b = 300 + i;
        i = i + 1;
    }
    i = 0;
    while i < 4 {
        ck(a[i].inner.x, 100 + i, 301);
        ck(a[i].inner.y, 200 + i, 302);
        ck(a[i].b, 300 + i, 303);
        i = i + 1;
    }
    return 0;
}

# 场景四：紧邻的局部变量不得被数组压到。
fn t_neighbors() -> i64 {
    let a: [3] W;
    let g0: i64 = 777;
    let g1: i64 = 888;
    a[2].b = 9;
    a[0].inner.x = 5;
    ck(g0, 777, 401);
    ck(g1, 888, 402);
    ck(a[2].b, 9, 403);
    ck(a[0].inner.x, 5, 404);
    return 0;
}

# 场景五：esz==8 的 i64 数组 —— 新旧公式在 esz==8 时相同，
# 这条是守护「修大元素别把小元素改坏」。
fn t_i64_array() -> i64 {
    let a: [3] i64;
    let g: i64 = 42;
    a[0] = 10;
    a[1] = 20;
    a[2] = 30;
    ck(a[0], 10, 501);
    ck(a[1], 20, 502);
    ck(a[2], 30, 503);
    ck(g, 42, 504);
    return 0;
}

# 场景六：byte 数组后面跟 i64 —— 对齐路径不能被破坏。
fn t_byte_array() -> i64 {
    let a: [8] byte;
    let g: i64 = 5;
    let i: i64 = 0;
    while i < 8 {
        a[i] = 65 + i;
        i = i + 1;
    }
    ck(g, 5, 601);
    i = 0;
    while i < 8 {
        let v: i64 = a[i];
        ck(v, 65 + i, 602);
        i = i + 1;
    }
    return 0;
}

fn main() -> i64 {
    t_first_local();
    t_prev_local();
    t_no_overlap();
    t_neighbors();
    t_i64_array();
    t_byte_array();
    if FAILS != 0 {
        print("stack_array_last: "); print_i64(FAILS); print(" failed\n");
        return 1;
    }
    print("stack_array_last: ok\n");
    return 0;
}
