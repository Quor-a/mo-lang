# 排序与查找：对标 C 的 qsort / bsearch
# expect: 1
#
# 注意：本测试用 load64/store64 直接寻址操作数组（而不是 a[i]），
# 所以**不享受越界检查** —— 规模必须自己保证不超过 A 的容量。
# 曾经把 [64] 的数组写成 512 个元素而段错误，就是这么来的。
import "sort.mo";
import "assert.mo";

var A: [1024] i64 = 0;

fn sorted(n: i64) -> i64 {
    let i: i64 = 1;
    while i < n {
        if load64(&A + i * 8) < load64(&A + (i - 1) * 8) { return 0; }
        i = i + 1;
    }
    return 1;
}

fn main() -> i64 {
    # 乱序
    let raw: [16] i64 = 0;
    let src: [16] byte = 0;
    # 手写一组乱序数
    let v: [16] i64 = 0;
    store64(&v, 5); store64(&v + 8, 3); store64(&v + 16, 9); store64(&v + 24, 1);
    store64(&v + 32, 7); store64(&v + 40, 2); store64(&v + 48, 8); store64(&v + 56, 6);
    store64(&v + 64, 4); store64(&v + 72, 0);

    let i: i64 = 0;
    while i < 10 { store64(&A + i * 8, load64(&v + i * 8)); i = i + 1; }

    qsort_i64(&A, 10);
    assert_eq("sorted", sorted(10), 1);
    assert_eq("min", load64(&A), 0);
    assert_eq("max", load64(&A + 9 * 8), 9);

    # 已排序 / 逆序 / 全相等，都是快排的经典退化输入
    i = 0;
    while i < 10 { store64(&A + i * 8, i); i = i + 1; }
    qsort_i64(&A, 10);
    assert_eq("already sorted", sorted(10), 1);

    i = 0;
    while i < 10 { store64(&A + i * 8, 10 - i); i = i + 1; }
    qsort_i64(&A, 10);
    assert_eq("reversed", sorted(10), 1);

    i = 0;
    while i < 10 { store64(&A + i * 8, 7); i = i + 1; }
    qsort_i64(&A, 10);
    assert_eq("all equal", sorted(10), 1);

    # 单元素与空
    store64(&A, 3);
    qsort_i64(&A, 1);
    assert_eq("single", load64(&A), 3);
    qsort_i64(&A, 0);

    # 降序
    i = 0;
    while i < 10 { store64(&A + i * 8, load64(&v + i * 8)); i = i + 1; }
    qsort_i64_desc(&A, 10);
    assert_eq("desc max", load64(&A), 9);
    assert_eq("desc min", load64(&A + 9 * 8), 0);

    # bsearch：注意 -1 才是没找到，0 是合法下标
    i = 0;
    while i < 10 { store64(&A + i * 8, i * 2); i = i + 1; }
    assert_eq("bsearch found", bsearch_i64(&A, 10, 8), 4);
    assert_eq("bsearch first", bsearch_i64(&A, 10, 0), 0);
    assert_eq("bsearch last", bsearch_i64(&A, 10, 18), 9);
    assert_eq("bsearch miss", bsearch_i64(&A, 10, 7), -1);
    assert_eq("bsearch miss2", bsearch_i64(&A, 10, 99), -1);

    # lsearch
    assert_eq("lsearch", lsearch_i64(&A, 10, 12), 6);
    assert_eq("lsearch miss", lsearch_i64(&A, 10, 13), -1);

    # argmin / argmax
    store64(&A, 5); store64(&A + 8, 2); store64(&A + 16, 9);
    assert_eq("argmin", argmin_i64(&A, 3), 1);
    assert_eq("argmax", argmax_i64(&A, 3), 2);

    # 规模：512 个随机数排序后应有序（顺带压一下快排递归深度）
    i = 0;
    let x: i64 = 12345;
    while i < 512 {
        x = x * 1103515245 + 12345;
        if x < 0 { x = 0 - x; }
        store64(&A + i * 8, x % 100000);
        i = i + 1;
    }
    qsort_i64(&A, 512);
    assert_eq("512 sorted", sorted(512), 1);

    let t_failed: i64 = test_done();
    if t_failed != 0 { return 2; }
    return 1;
}
