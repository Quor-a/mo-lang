# thread.mo —— 线程与同步
#
# 底层用 POSIX threads（pthread）。墨语言的调用约定本来就是 System V，
# 局部变量是 rbp 相对寻址 —— 所以**线程天然安全**：每个线程有自己的栈，
# 局部变量互不干扰，需要加锁的只有全局变量和堆。
#
# 需要链接 pthread：
#   ./bin/moc prog.mo -c prog.o && bash tools/molink.sh prog.o -o prog
#
# 🔴 已知限制：
#   - heap.mo 的 malloc/free **不是线程安全的**（全局 brk + 全局链表），
#     多线程里不要 malloc，或者全部加锁后使用。
#   - 回调必须是**本文件里的函数**（`&fn` 取地址），不能是局部变量。

extern fn pthread_create(t: ptr, attr: ptr, f: ptr, arg: ptr) -> i32;
extern fn pthread_join(th: i64, ret: ptr) -> i32;
extern fn pthread_mutex_init(m: ptr, attr: ptr) -> i32;
extern fn pthread_mutex_lock(m: ptr) -> i32;
extern fn pthread_mutex_unlock(m: ptr) -> i32;

# futex：Linux 原生等待/唤醒，不经过 libc。
#   单独用意义不大（没有原子操作做不了真正的锁），
#   但配合 mutex 可以做条件等待。
fn futex_wait(p: ptr, val: i64) -> i64 {
    return syscall(202, p, 0, val, 0, 0, 0);
}

fn futex_wake(p: ptr, n: i64) -> i64 {
    return syscall(202, p, 1, n, 0, 0, 0);
}

# nanosleep：睡眠 usec 微秒（纯系统调用，不需要 libc）
# TS 必须先声明 —— 墨语言是"先定义后使用"。
var TS: [2] i64 = 0;

fn usleep(usec: i64) -> i64 {
    TS[0] = usec / 1000000;
    TS[1] = (usec % 1000000) * 1000;
    return syscall(35, &TS, 0, 0, 0, 0, 0);
}

# v1.216：usleep_safe —— 栈上独立 timespec（两个 i64 局部取址），并发协程/线程
# 可同时调用（全局 TS 会互踩：tv_nsec 被写成天文数字 → nanosleep 卡死 60s+，
# mopkg publish 卡死实锤）。
var TS2: [16] i64 = 0;   # 4 槽 × 2（tv_sec, tv_nsec）轮转
var TSEQ: i64 = 0;
fn usleep_safe(usec: i64) -> i64 {
    let slot: i64 = TSEQ % 4;
    TSEQ = TSEQ + 1;
    store64(&TS2 + slot * 2, usec / 1000000);
    store64(&TS2 + slot * 2 + 1, (usec % 1000000) * 1000);
    return syscall(35, &TS2 + slot * 2, 0, 0, 0, 0, 0);
}

# ---- 封装 ----
# pthread_mutex_t 在 glibc 下是 40 字节；[8] i64 = 64 字节足够。
# 用 `var M: [8] i64 = 0;` 声明，零初始化即 PTHREAD_MUTEX_INITIALIZER。

fn thread_create(t: ptr, f: ptr, arg: ptr) -> i64 {
    return pthread_create(t, 0, f, arg);
}

fn thread_join(t: i64) -> i64 {
    return pthread_join(t, 0);
}

fn mutex_init(m: ptr) -> i64 {
    return pthread_mutex_init(m, 0);
}

fn mutex_lock(m: ptr) -> i64 {
    return pthread_mutex_lock(m);
}

fn mutex_unlock(m: ptr) -> i64 {
    return pthread_mutex_unlock(m);
}
