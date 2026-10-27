# arenademo —— 同一个任务，两种内存管理方式的对照
#
# 任务：解析 2000 条记录，每条在堆上建一个对象。
#
#   写法 A：逐个 malloc，**忘了 free** —— 真实代码里最常见的形态
#   写法 B：用 arena，处理完一次 reset / free
#
# 两种写法**运行结果完全一样**（都是 2000 条），
# 差别只在内存：A 泄漏 2000 个对象，B 一个都不漏。
# 而这个差别**不报错、不崩溃、结果也对** —— 只能靠 leak 看出来。
import "io.mo";
import "heap.mo";
import "arena.mo";
import "leak.mo";

var NREC: i64 = 2000;

# 写法 A：忘记释放（模拟真实 bug）
fn parse_naive() -> i64 {
    let i: i64 = 0;
    while i < NREC {
        let p: i64 = lmalloc(64);
        store64(p, i);          # 假装填入解析结果
        i = i + 1;
    }
    return NREC;
}

# 写法 B：arena —— 对象不单独释放，整批一次性丢弃
fn parse_arena() -> i64 {
    let a: Arena;
    Arena_init(&a, 65536);
    let i: i64 = 0;
    while i < NREC {
        let p: ptr = Arena_alloc(&a, 64);
        store64(p, i);
        i = i + 1;
    }
    Arena_free(&a);             # 一次调用，替代 2000 次 free
    return NREC;
}

# 写法 C：反复 reset —— 批处理场景（每批用完就丢）
fn parse_batched() -> i64 {
    let a: Arena;
    Arena_init(&a, 65536);
    let batch: i64 = 0;
    while batch < 100 {
        let i: i64 = 0;
        while i < 20 {
            let p: ptr = Arena_alloc(&a, 64);
            store64(p, batch * 20 + i);
            i = i + 1;
        }
        Arena_reset(&a);        # 这批用完了，整批丢弃
        batch = batch + 1;
    }
    Arena_free(&a);
    return 100 * 20;
}

fn main() -> i64 {
    heap2_init();
    leak_init();

    print("======== 写法 A：逐个 malloc，忘了 free ========\n");
    print("解析 "); print_i64(parse_naive()); print(" 条\n");
    print("未释放对象："); print_i64(leak_count()); print(" 个\n");
    print("未释放字节："); print_i64(leak_bytes()); print(" 字节\n\n");

    leak_clear();
    print("======== 写法 B：arena，一次 free ========\n");
    print("解析 "); print_i64(parse_arena()); print(" 条\n");
    print("未释放对象："); print_i64(leak_count()); print(" 个\n");
    print("未释放字节："); print_i64(leak_bytes()); print(" 字节\n\n");

    leak_clear();
    print("======== 写法 C：arena 反复 reset（100 批）========\n");
    print("处理 "); print_i64(parse_batched()); print(" 条\n");
    print("未释放对象："); print_i64(leak_count()); print(" 个\n");
    print("未释放字节："); print_i64(leak_bytes()); print(" 字节\n");

    return 0;
}
