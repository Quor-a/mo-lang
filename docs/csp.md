# CSP 并发：协程调度器 + channel

`lib/csp.mo`。概念来自 Hoare 的 *Communicating Sequential Processes*（1978）——
进程（这里是协程）之间**不共享内存**，只通过 channel 通信。
Go 的 goroutine/channel 是它的工程化形态；本库用 `ucontext` 在墨语言里
实现同样的语义。

需要 libc 与 pthread（`ucontext` 在 libc 里）：

```bash
./bin/moc prog.mo -c prog.o
bash tools/molink.sh prog.o -o prog
```

## 用法

```mo
import "io.mo";
import "csp.mo";

var C: i64 = 0;
var SUM: i64 = 0;

fn producer() -> i64 {
    let base: i64 = csp_arg();        # 取 csp_go 传进来的参数
    let i: i64 = 0;
    while i < 5 { chan_send(C, base + i); i = i + 1; }
    csp_exit();                       # 🔴 必须用它结束，不能靠 return
    return 0;
}

fn consumer() -> i64 {
    let i: i64 = 0;
    while i < 10 {
        let v: i64 = chan_recv(C);
        SUM = SUM + v;
        i = i + 1;
    }
    csp_exit();
    return 0;
}

fn main() -> i64 {
    csp_init(2);                      # 2 个 worker 线程
    C = chan_make(4);                 # 缓冲 4；传 0 为无缓冲
    csp_go(&producer, 100);
    csp_go(&producer, 200);
    csp_go(&consumer, 0);
    csp_sched();                      # 等全部结束并回收 worker
    return 0;
}
```

| 函数 | 说明 |
|---|---|
| `csp_init(nw)` | 启动 nw 个 worker 线程（≤4） |
| `csp_go(f, arg)` | 创建协程，轮流绑定到 worker；`f` 必须无参，参数用 `csp_arg()` |
| `csp_exit()` | 协程结束（**必须调用**） |
| `csp_sched()` | 等所有协程完成，返回 -1 表示死锁 |
| `csp_yield()` | 主动让出（仍在可运行状态） |
| `chan_make(cap)` | 建 channel，`cap=0` 为无缓冲 rendezvous |
| `chan_send(c, v)` | 发送；满则阻塞；已关闭返回 -1 |
| `chan_recv(c)` | 接收；空则阻塞；`CH_OK` 表示是否拿到值 |
| `chan_close(c)` | 关闭；阻塞中的收发会被唤醒并返回失败 |
| `chan_tryrecv(c)` | 非阻塞接收，返回值在 `CSP_TRYV` |

## 实测（`make csptest`，8 项）

| 场景 | 结果 |
|---|---|
| 缓冲 channel：2 生产者 × 5 条，1 消费者求和 | 1520 ✓ |
| FIFO 顺序（0,1,2,3,4 按到达序） | ✓ |
| 接收者先启动（channel 空 → 阻塞 → 不丢消息） | 10 ✓ |
| 无缓冲 rendezvous 求和（1..5） | 15 ✓ |
| close 后 recv 的 `CH_OK` | 0 ✓ |
| 3 worker 跨线程求和 | 312 ✓ |

判据是**具体数字**，不是"有没有崩"：漏消息、顺序错、唤醒失效都只表现为数字不对。

变异验证见 `tools/cspmut.sh`（`make cspmut`，不进 `all`，约 2~3 分钟）：
三个变异全部被捕获 —— 缓冲改 LIFO → 4 项红；去掉唤醒 → 8 项红；
去掉无缓冲交接标记 → 3 项红。

## 🔴 编译器破坏 callee-saved 的 rbx（v1.113.0 已修）

**现象**：空协程 `return` 正常；但只要协程里调用过 `print` 之类**用了 rbx 的
墨函数**，`return` 就 SIGSEGV。

**根因**：glibc 的 `__start_context`（协程 `return` 后执行到这里）
从 **`%rbx`** 取 `uc_link`。而墨语言生成的代码用 rbx 做表达式求值中转
（`mov %rax,%rbx`），**既不 push 保存也不 pop 恢复** —— rbx 是 callee-saved
寄存器，这违反 System V ABI。

**影响面不止 ucontext**：任何被 C 代码回调的墨语言函数（qsort 比较器、
pthread 回调、信号处理器）都会破坏调用者的 rbx。

**修法**：`g_prologue` 在 `sub rsp` **之前** `push rbx`（保存值固定落在
`[rbp-8]`），`g_epilogue` 用 `lea rsp,[rbp-8]; pop rbx; pop rbp; ret`
—— 直接 `mov rsp,rbp` 会 pop 到"保存的 rbp"，顺序正好反了。
汇编版 seed（`src/asm/base.s`）同步改。

**连带两处必须一起改**，否则自举直接挂：
- 局部槽与参数槽从 `[rbp-16]` 起（原 `-8` 会写进 rbx 槽）
- 帧大小改为 `((frame+7) & -16) + 8`（多了一个 push，要维持 call 时
  `rsp%16==0`；仍按 ≡0 对齐会整体偏 8 字节）

### 🔴 最阴的一处：参数槽漏改，症状是"编译器全线段错误"

`emit_store_arg(-8*(i+1))` 只改了注释没改算术 —— 第 0 个参数仍写进 `[rbp-8]`，
**覆盖掉刚保存的 rbx**。于是任何**带参数**的函数返回时都跳到垃圾地址。

实测：`bin/moc` 编译**任何**输入都 SIGSEGV（连 `fn main() -> i64 { return 0; }`
都崩），45 个示例全线编译失败。而不带参的函数一切正常，所以只跑空函数
永远绿 —— 这正是它在上一版里被当成"已修好"的原因。

变异验证：把 `-8*(i+2)` 改回 `-8*(i+1)` 重编，`tools/rbxtest.sh` **8 项全红**
（含空协程那两项）。

**回归测试**：`tools/rbxtest.sh`（`make rbxtest`）。两组用例：
裸 `ucontext` 下协程直接 `return`（空协程作对照）、以及 `csp.mo` 里协程
不调 `csp_exit` 直接 `return` 求和 = 15。判据是"走完全程 + 退出码 0"。
空协程那两条是**对照组**——修复前后都该绿，没有它们就分不清
"rbx 已恢复"和"压根没测到"。

## 其他设计约束

- **协程绑定 worker，不做工作窃取**：`makecontext` 的 `uc_link` 写死了该
  worker 的调度上下文，跨线程恢复会跑到别的线程栈上。
- **状态机区分 return 与 yield**：`1=new 2=running 3=wait 4=done 6=yielded`。
  两者从同一处恢复，只能靠状态区分——`swapcontext` 返回后仍是 2 说明协程
  `return` 了（uc_link 生效）。
- **唤醒用惊群**：channel 操作成功后把所有等在该 channel 上的协程置为可运行，
  各自重新检查条件。正确但非最优，换来不需要精确的等待队列。
- **死锁必须报出来**：worker 空转或 `csp_sched` 等待超时会置 `CSP_DEAD` 并返回
  -1，绝不静默挂住。测试里 `dead=0` 是硬断言。

## 限制

- 协程函数必须**无参**（C 视角 `void(void)`），参数走 `csp_arg()`。
- `csp_exit()` 仍保留（显式切回调度器）；1.113.0 起直接 `return` 同样安全。
- `heap.mo` 的 malloc 非线程安全，多 worker 下不要 malloc。
- 上限：32 协程 / 16 channel / 缓冲容量 64 / 4 worker。
- 无 `select`、无定时器、无协程局部存储。
- `CSP_WK = slot % nw` 是静态绑定，负载不均时不做迁移。
