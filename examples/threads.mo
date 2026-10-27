# 线程示例：3 个线程对共享计数器加锁自增
#
# 编译运行：
#   ./bin/moc examples/threads.mo -c /tmp/th.o
#   bash tools/molink.sh /tmp/th.o -o /tmp/th && /tmp/th

import "io.mo";
import "thread.mo";

var CNT: i64 = 0;
var MTX: [8] i64 = 0;
var T1: i64 = 0;
var T2: i64 = 0;
var T3: i64 = 0;

fn worker(arg: ptr) -> i64 {
    let i: i64 = 0;
    while i < 20000 {
        mutex_lock(&MTX);
        CNT = CNT + 1;
        mutex_unlock(&MTX);
        i = i + 1;
    }
    return 0;
}

fn main() -> i64 {
    if mutex_init(&MTX) != 0 { print("mutex_init failed\n"); return 1; }
    if thread_create(&T1, &worker, 0) != 0 { return 1; }
    if thread_create(&T2, &worker, 0) != 0 { return 1; }
    if thread_create(&T3, &worker, 0) != 0 { return 1; }
    thread_join(T1); thread_join(T2); thread_join(T3);
    print("CNT = "); print_i64(CNT); print("\n");
    if CNT != 60000 { return 1; }
    return 0;
}
