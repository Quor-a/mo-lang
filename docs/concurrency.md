# 并发：线程与同步

```mo
import "thread.mo";

var CNT: i64 = 0;
var MTX: [8] i64 = 0;     # pthread_mutex_t
var T1: i64 = 0;

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
    mutex_init(&MTX);
    thread_create(&T1, &worker, 0);
    thread_join(T1);
    return 0;
}
```

编译运行：

```bash
./bin/moc prog.mo -c prog.o
bash tools/molink.sh prog.o -o prog     # 已自动加 -lpthread
```

## 为什么线程天然安全

墨语言的局部变量是 **rbp 相对寻址**，每个线程有自己的栈 ——
所以局部变量互不干扰，**只有全局变量和堆需要加锁**。

底层用 POSIX threads。墨语言的调用约定本来就是 System V，
所以 `&worker` 这样的函数指针可以直接交给 C（见"函数指针"一节）。

## 函数指针 `&func`

```mo
extern fn qsort(base: ptr, n: i64, sz: i64, cmp: ptr) -> i64;
qsort(&ARR, 4, 8, &cmp);      # 把墨函数当比较器传给 C
```

`&funcname` 取函数地址。此前这是硬限制（函数名不是值），
qsort / pthread / atexit 这类需要回调的 C 函数都用不了。

实现方式：
- 直接生成 ELF 时：已定义的函数直接填绝对地址；前向引用走回填表
- `-c` 生成 .o 时：发 `movabs rax,0` + **R_X86_64_64** 重定位，
  让 ld 填真实地址（`.text` 会被链接器搬走，编译期算不出来）

## 🔴 全局变量必须对齐 —— 否则 futex 直接 abort

```
The futex facility returned an unexpected error code.
```

这个报错**看起来像锁用错了，实际是数据段没对齐**。

全局变量前面可能有任意长度的字符串常量，变量地址因此可能不是
8 的倍数（实测出现过 `0x1000019D`）。x86 允许未对齐访问，
所以 `i64` 变量只是慢一点、完全看不出问题；但 `pthread_mutex_t`
里含 futex word，**内核要求地址对齐**，未对齐就让 glibc 直接 abort。

修法：`parse_global` 在分配每个全局变量前把数据段对齐到 16
（`data_align`）。

> 同步改了 seed 汇编（`src/asm/stmt.s`）—— 这是"改编译期副作用
> 必须两边同步"的又一次应验：只改 moc 的话自举立刻不一致。

## 验证：`tools/threadtest.sh`（4 项）

最关键的是**无锁对照**：

```
✓ 3 线程 × 20000 次加锁自增，结果精确（60000）
✓ 无锁对照确实丢更新（3170466 != 4000000）
✓ 全局变量地址 16 对齐
```

只测"加锁后结果正确"是不够的 —— 也许根本没并发、也许锁是空操作。
**必须同时证明"不加锁会错"**，才能说明锁真的在起作用。

## 已知限制

- **heap.mo 的 malloc/free 不是线程安全的**（全局 brk + 全局链表）。
  多线程里不要 malloc，或者全部加锁后使用
- 回调必须是本文件里的函数（`&fn` 取地址），不能是局部变量
- 线程创建依赖 pthread（`-c` + `molink`），**freestanding 目标没有线程**
- `futex_wait` / `futex_wake` 已导出，但没有原子操作内建，
  单独用做不了锁 —— 需要配合 mutex
- `usleep` 内部的 `TS` 是全局变量，**多线程同时 sleep 会互相覆盖**
