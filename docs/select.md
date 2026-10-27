# select —— CSP 的选择结构（guarded command）

## 概念来源

- Dijkstra, *Guarded commands...* (1975)：`if` 的守卫形式 —— 若干 `(guard → statement)`，
  只执行守卫成立的**其中一条**；全不成立则阻塞，有 `else` 则走 `else`。
- Hoare, *Communicating Sequential Processes* (1978)：把 guard 换成通信事件。
- 工程化后裔：Alef / Plan 9 libthread 的 `alt()`、Go 的 `select {}`。

形态分布：Go 是**语言级内建**；Rust 是库级宏（`tokio::select!` / `crossbeam::select!`）；
C/C++ 除 libtask / libthread 外基本空白。本库在**无语言支持**的前提下用 ucontext 实现出来。

## 用法

```mo
import "csp.mo";
import "select.mo";

sel_reset();
sel_case(CA, 1, 0);      # op=1 接收
sel_case(CS, 0, 55);     # op=0 发送值 55
let k: i64 = sel_go(0);  # 0 = 无 default；返回命中的 case 下标
                         # -1 = 走 default；-2 = 出错 / 非协程上下文
let v: i64 = sel_val();  # recv 命中的值
```

必须走 `molink + libc`（ucontext / pthread 在 libc 里）。

## 核心难点：一个协程同时等 N 个 channel

`csp.mo` 的 `CSP_WCH[]` 每协程只有**一个**槽。所以调度器另开一张多通道表
`CSP_SLC[] / CSP_SN[] / CSP_SACT[] / CSP_SWIN[]`，select 把自己登记成 `ACT=1`，
`csp_wakech()` 末尾的 `csp_wakesel()` 按 channel 号反查哪个协程的哪个 case 命中。

**表必须放在 `csp.mo`**，两个原因：
1. 唤醒路径只在调度器那一侧；
2. 墨语言不支持函数指针调用 —— `if CSP_WKCB != 0 { CSP_WKCB(c); }` 直接报
   `undefined symbol`，第一版想用回调钩子，编译就过不去。

数组全 0 时 `csp_wakesel()` 什么也不做，不用 select 的程序不受影响。

## 三个必须闭合的竞态

| 竞态 | 后果 | 闭合方式 |
|---|---|---|
| ① 漏唤醒：已注册但还没 park 时事件到达 | 协程随后 park，永远睡着 | 协程在**锁内**宣告 `CSP_ST=7` 再 park；唤醒方只在 `ST==7` 时才 enq，否则只置 `CSP_SWIN` 让它自己重试 |
| ② 值被抢：醒来时已被别的协程取走 | 拿到错值 / 空转 | 醒来一律**重新 try 一遍**，失败则清标记再 park |
| ③ 同一次 select 被多个 case 同时命中 | 一个协程被入队多次 | `CSP_SWIN` 只 claim 一次（`ACT` 1→2） |

① 与 `lib/aio.mo` v1.124 修的是同一类窗口（那次是"等待者表没锁"），
解法相同：**在锁内宣告"我将挂起"**。

## 实测（`make selecttest`，17 项）

| 场景 | 结果 |
|---|---|
| 两个 case 都就绪，100 次 | c0=43 / c1=57（和为 100，两个都必须 > 0） |
| 只有一个就绪 | 必命中它（case 1，值 777） |
| 都不就绪 + default | 立即返回 -1，不阻塞 |
| 都不就绪、无 default | 阻塞到后到的 channel（case 1，值 4242） |
| closed channel 上的 recv | 视为就绪，给零值 |
| 3 worker、两消费者抢 20 个值 | 收到 20、和 190、**重复 0** |
| send/recv 混合（缓冲满后） | 改走 recv，取到 999 |

公平性由**随机起点**轮询给出：实测 43/57 而非 50/50（xorshift64 低位质量有限）。
断言写成"两个都必须 > 0 且和为 100"，而不是"必须接近一半"——前者才是不饥饿的本质判据。

## 变异验证（`make selectmut`）

| 变异 | 结果 |
|---|---|
| M1 随机起点 → 固定起点 | ✅ 捕获：c0=100 / c1=0，公平性断言变红 |
| M2 不调 `csp_wakesel()` | ✅ 捕获：阻塞场景死锁，4 项变红 |
| M3 去掉"只有已挂起才入队" | ❌ **未捕获**，17 项仍全绿 |

M3 未捕获不是"这条检查没必要"：多出来的 enq 让已结束的协程从 `csp_exit` 的
`while 1 { usleep }` 恢复，不影响任何计数。**如实记录，没有假装它通过。**

（M3 的第一版是"去掉 claim 标记"，同样未捕获 —— 因为 `ST==7` 判定已经防住了
重复入队，claim 只是第二道冗余保险。变异必须打在真正的因果链上。）

## 踩到的坑

**变异脚本被中断 → 源码停在变异状态。** 跑 `selectmut.sh` 时命令超时被杀，
`csp.mo` 停在 M2 变异态，而备份目录已在收尾时删除 —— 下一轮基线直接 17 项全红。
已加 `trap restore EXIT INT TERM` 兜底，并在收尾处判断备份是否存在。
这是本项目第二次栽在"验证脚本自身的静默失效"上。

## 已知限制

- 每 select 最多 8 个 case（`CSP_SELK`）；协程上限同 `CSP_MAXC`（128）。
- closed channel 上的 recv 给零值；向 closed channel 的 send 视为就绪并置 `SEL_ERR`
  （Go 是 panic，墨语言没有 panic，选择响出来而不是静默跳过）。
- 唤醒用"惊群"：channel 操作成功后唤醒所有等在该 channel 上的 select 协程。
- `rand()` 是全局状态，多 worker 下种子竞争 —— 只影响公平性均匀度，不影响正确性。
