# 90 —— arena（区域分配器）与 leak（泄漏检测）
#
# 为什么需要它们：lib/heap.mo 的 malloc/free 要求调用方对**每一个**
# 对象都记得 free。漏掉一个是**静默错误** —— 不报错、不崩溃、结果也对，
# 只是内存一路涨，跑到 OOM 时早已离出错点很远。
import "assert.mo";
import "heap.mo";
import "arena.mo";
import "leak.mo";

fn main() -> i64 {
    heap2_init();

    # ---------- arena：基本分配 ----------
    let a: Arena;
    assert_eq("arena init", Arena_init(&a, 4096), 0);

    let p1: ptr = Arena_alloc(&a, 64);
    assert_eq("p1 非空", p1 != 0, 1);
    store64(p1, 12345);
    assert_eq("p1 可写可读", load64(p1), 12345);

    let p2: ptr = Arena_alloc(&a, 64);
    # 不同对象必须落在不同地址（否则会互相覆盖）
    assert_eq("p2 与 p1 不重叠", p2 - p1 >= 64, 1);
    store64(p2, 999);
    assert_eq("p1 未被 p2 破坏", load64(p1), 12345);
    assert_eq("p2 可写可读", load64(p2), 999);

    # ---------- arena：对齐 ----------
    let p3: ptr = Arena_alloc(&a, 1);      # 大小 1，仍应按 16 对齐
    assert_eq("对齐到 16", p3 % 16, 0);

    # ---------- arena：字符串 ----------
    let s: ptr = Arena_str(&a, "hello arena");
    assert_eq("Arena_str 内容", streq(s, "hello arena"), 1);

    # ---------- arena：reset 之后内存不增长（核心）----------
    #
    # 这是 arena 存在的理由：循环「分配一批 → 一次性丢弃」，
    # 内存占用应当**恒定**，而不是随轮数线性上涨。
    # 用 malloc/free 写同样的循环，漏一个 free 就会涨 ——
    # 而且不报错，只能靠这里这种断言发现。
    let u0: i64 = heap2_used();
    let it: i64 = 0;
    while it < 2000 {
        let i: i64 = 0;
        while i < 20 {
            let q: ptr = Arena_alloc(&a, 64);
            store64(q, it + i);
            i = i + 1;
        }
        Arena_reset(&a);
        it = it + 1;
    }
    let u1: i64 = heap2_used();
    # 允许少量增长（块按 64KB 申请），但不能随 2000 轮线性上涨
    assert_eq("2000 轮后不线性增长", u1 - u0 < 262144, 1);

    # reset 之后应当从开头重新分配（复用同一块）
    let r1: ptr = Arena_alloc(&a, 16);
    let r2: ptr = Arena_alloc(&a, 16);
    assert_eq("reset 后紧凑复用", r2 - r1, 16);

    # ---------- arena：跨块分配 ----------
    let big: ptr = Arena_alloc(&a, 200000);   # 远超单块容量
    assert_eq("跨块分配成功", big != 0, 1);
    store64(big, 7);
    assert_eq("跨块可写", load64(big), 7);
    assert_eq("确实开了新块", Arena_nblk(&a) > 1, 1);

    Arena_free(&a);
    assert_eq("free 后归零", Arena_nblk(&a), 0);

    # ---------- leak：配对释放 ----------
    let b: Arena;
    Arena_init(&b, 4096);
    leak_init();
    assert_eq("初始无分配", leak_count(), 0);

    let m1: i64 = lmalloc(100);
    assert_eq("分配后 1 条", leak_count(), 1);
    assert_eq("字节数正确", leak_bytes(), 100);
    lfree(m1);
    assert_eq("释放后 0 条", leak_count(), 0);
    assert_eq("字节归零", leak_bytes(), 0);

    # ---------- leak：故意泄漏 ----------
    let x: i64 = lmalloc(64);
    let y: i64 = lmalloc(128);
    let z: i64 = lmalloc(256);
    assert_eq("3 条未释放", leak_count(), 3);
    assert_eq("活跃字节", leak_bytes(), 448);

    # 释放其中一个，其余仍在
    lfree(y);
    assert_eq("释放后剩 2 条", leak_count(), 2);
    assert_eq("剩余字节", leak_bytes(), 320);

    # ---------- leak：释放未追踪的地址不应崩 ----------
    let raw: i64 = malloc(32);
    lfree(raw);                 # 裸 malloc，leak 表里没有 → 直接 free
    assert_eq("裸 free 不影响计数", leak_count(), 2);

    # ---------- leak：报告 ----------
    let n: i64 = leak_report();
    assert_eq("报告返回活跃条数", n, 2);

    Arena_free(&b);
    return test_done();
}
