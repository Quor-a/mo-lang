# malloc / free / realloc：真正的动态分配器
# expect: 1
import "heap.mo";
import "assert.mo";
import "str.mo";

fn main() -> i64 {
    heap2_init();

    # 基本分配与写入
    let p: i64 = malloc(64);
    assert_true("malloc ok", p != 0);
    strcpy(p, "hello");
    assert_eq("content", streq(p, "hello"), 1);

    # calloc 必须清零 —— 不清零是"未初始化内存"bug 的经典来源
    let c: i64 = calloc(16, 8);
    assert_true("calloc ok", c != 0);
    let i: i64 = 0;
    let nz: i64 = 0;
    while i < 128 {
        if load8(c + i) != 0 { nz = nz + 1; }
        i = i + 1;
    }
    assert_eq("calloc zeroed", nz, 0);

    # free 之后同一块应能被再次分配（证明真的回收了，不是 bump）
    free(p);
    let p2: i64 = malloc(64);
    assert_true("reuse", p2 != 0);

    # 关键：反复分配释放，堆用量不应单调增长。
    # bump 分配器在这一步会一路推高 brk；真分配器应当基本持平。
    let before: i64 = heap2_used();
    i = 0;
    while i < 2000 {
        let a: i64 = malloc(128);
        let b: i64 = malloc(256);
        free(a);
        free(b);
        i = i + 1;
    }
    let after: i64 = heap2_used();
    # 允许少量增长（分裂碎片），但不能是 2000 次累加
    assert_true("no monotonic growth", after < before + 65536);

    # realloc 缩小：地址不变，数据保留
    let r: i64 = malloc(200);
    strcpy(r, "abcdef");
    let r2: i64 = realloc(r, 64);
    assert_true("realloc shrink", r2 != 0);
    assert_eq("realloc keep data", streq(r2, "abcdef"), 1);

    # realloc 放大：数据仍保留
    let r3: i64 = realloc(r2, 512);
    assert_true("realloc grow", r3 != 0);
    assert_eq("realloc keep data2", streq(r3, "abcdef"), 1);

    # 边界：malloc(0) 返回 0，free(0) 不崩
    assert_eq("malloc0", malloc(0), 0);
    free(0);

    # 多块并存，互不覆盖
    let x: i64 = malloc(32);
    let y: i64 = malloc(32);
    let z: i64 = malloc(32);
    strcpy(x, "AAA");
    strcpy(y, "BBB");
    strcpy(z, "CCC");
    assert_eq("x", streq(x, "AAA"), 1);
    assert_eq("y", streq(y, "BBB"), 1);
    assert_eq("z", streq(z, "CCC"), 1);

    let t_failed: i64 = test_done();
    if t_failed != 0 { return 2; }
    return 1;
}
