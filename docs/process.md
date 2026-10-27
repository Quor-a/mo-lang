# 进程分配与开发使用

版本 1.21.0（2026-10-09）

`lib/proc.mo` 提供完整的进程管理能力，**并用它写出了真实的多进程程序**
`examples/parallel.mo`（并行筛素数，结果必须与串行一致）。

## 能力一览

| 类别 | 函数 |
|---|---|
| 标识 | `proc_pid` / `proc_ppid` / `proc_fork` / `proc_getpgid` / `proc_setpgid` / `proc_setsid` |
| 调度 | `proc_nice` / `proc_setprio` / `proc_getprio` |
| 资源 | `proc_rusage` / `proc_utime_ms` / `proc_stime_ms` / `proc_maxrss` / `proc_child_utime_ms` / `proc_setrlimit` |
| 等待 | `proc_wait` / `proc_wait_opt`（含 WNOHANG）/ `proc_poll` / `proc_status` / `proc_signal` / `proc_kill` |
| 守护化 | `daemonize()` |
| **进程池** | `pool_start` / `pool_send` / `pool_recv` / `pool_stop` |

全部是系统调用，不依赖 libc。

## 进程池：怎么在没有函数指针的语言里做回调

墨语言没有函数指针，worker 里不能调用"传进来的函数"。

但墨语言的**所有函数都在全局符号表里**——于是约定：

> 使用进程池的程序**自己定义** `fn pool_work(task: i64) -> i64`。

worker 循环直接调用它。这不是函数指针，是"约定的全局函数"。

### 结构与用法

每个 worker 一对管道：

```
下发：父写 TO_W[i]  →  子读 TO_R[i]
回传：子写 BK_W[i]  →  父读 BK_R[i]
```

任务是 `i64`，结果也是 `i64`。

```mo
import "proc.mo";

fn pool_work(task: i64) -> i64 {      # 必须定义，名字固定
    return task * task + 1;
}

fn main() -> i64 {
    let n: i64 = pool_start(4);       # fork 4 个 worker
    let i: i64 = 0;
    while i < n {
        pool_send(i, i);              # 把任务 i 交给 worker i
        i = i + 1;
    }
    let sum: i64 = 0;
    i = 0;
    while i < n {
        sum = sum + pool_recv(i);     # 收集结果
        i = i + 1;
    }
    pool_stop();                      # 关下发端 + 回收子进程
    return 0;
}
```

### 踩到的坑：fd 号复用导致关错管道

这是本轮最值钱的发现，而且**只在 worker 数 ≥ 2 时才暴露**。

第一版让子进程去关闭"兄弟 worker"的 fd：

```mo
# 错误做法
while j < n {
    if j != i {
        close(P_TO_R[j]);   # 关掉兄弟的读端
    }
}
```

两个问题：

1. **兄弟可能还没创建** —— `P_TO_R[j]` 是 0，于是 `close(0)` 关掉了 stdin
2. **更要命：fd 号会被复用** —— 父进程关掉某个 fd 后，下一次 `pipe()`
   会拿到同一个号。于是按"记录的值"去 close，会关掉**自己**的管道

实测 n=2 时：子进程 1 执行 `close(P_TO_R[0])` 关掉了自己的读端
（因为 fd 3 已被复用给管道 1），立刻 EOF 退出；父进程写入得到
**SIGPIPE（退出码 141）**。

**正确做法**：子进程只关自己的反向端，父进程在 `fork` 后**立即**关掉
子专用的两个端。这样后续 fork 的子进程自然不会继承到，无需子进程操心。

```mo
# 子进程（只关自己的）
close(P_TO_W[i]);   # 下发写端是父用的
close(P_BK_R[i]);   # 回传读端是父用的

# 父进程（fork 后立刻关）
close(P_TO_R[i]);
close(P_BK_W[i]);
```

### 另一个坑：waitpid 是裸系统调用

`waitpid` 出错时返回的是**负的 errno**，不是 C 库封装后的 -1。
没有子进程时返回 **-10（-ECHILD）**。

所以 `proc_poll()` 的返回值不能用 `>= 0` 判断成功。

### fork 后的"角色分支"

墨语言不需要 `ROLE` 变量来做进程角色判断——`fork` 返回后子进程继续
执行后面的代码，直接 `if pid == 0 { ... }` 即可：

```mo
let pid: i64 = proc_fork();
if pid == 0 {
    worker_stuff();      # 子进程
    proc_exit(0);
}
# 父进程继续
```

## 开发使用：examples/parallel.mo

把 `[1, 200000]` 切成 4 段，每段交给一个 worker 数素数，父进程汇总。
**最后与单进程串行结果比对，必须一致。**

```
parallel prime counting with a process pool
range = 1..200000   workers = 4
forked 4 worker processes
  worker 0 (pid 1332) found 5133
  worker 1 (pid 1333) found 4459
  worker 2 (pid 1334) found 4256
  worker 3 (pid 1335) found 4136
parallel total = 17984
serial   total = 17984
MATCH: parallel == serial
```

`π(200000) = 17984`，数学上也正确。

> **验证方式很重要**：并行程序不能只验"跑起来了"，要验
> **并行结果 == 串行结果**。否则任务分片错误、结果丢失都看不出来。

## 其它开发用法

### 守护化

```mo
daemonize();     # 父进程直接退出，子进程脱离终端继续
# 之后的代码运行在守护进程里
```

### 优先级

```mo
let r: i64 = proc_nice(5);          # 提高 nice 值（降低优先级）
proc_setprio(pid, 10);
```

### 资源统计

```mo
print_i64(proc_utime_ms());         # 自身用户态 CPU 毫秒
print_i64(proc_child_utime_ms());   # 已回收子进程的累计 CPU
```

**实测提示**：在部分容器 / 沙盒环境里内核不填 `ru_maxrss`，
`proc_maxrss()` 恒为 0。所以不要拿它做断言。

### 限制资源

```mo
proc_setrlimit(0, 10, 10);   # RLIMIT_CPU：最多 10 秒 CPU
```

## 已知限制

- 进程池的任务与结果都只能是 `i64`，不能传字符串/结构体
  （管道里只收发 8 字节；要传大数据得自己建共享内存或用文件）
- `pool_work` 是**约定的全局函数名**，不支持传入自定义名字，
  也不支持一个程序里有多套池
- worker 数上限 32（`P_TO_W` 等数组维度）
- 没有超时机制：worker 挂死会让 `pool_recv` 永久阻塞
- 没有任务窃取（work stealing）：任务分配是静态的，
  某段特别慢时其他 worker 会空转

## 验证

`tests/71_proc.mo`（16 条断言）：进程标识、进程组、fork/wait 退出码、
非阻塞探活、资源统计、进程池 2 worker 与 3 worker 两轮。
