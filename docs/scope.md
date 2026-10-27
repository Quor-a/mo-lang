# scope.mo —— 结构化并发（Structured Concurrency / nursery）

`lib/scope.mo`（v1.128.0）。需 `molink + libc`（ucontext / pthread）。

```mo
import "scope.mo";

fn child() -> i64 { PART[csp_arg()] = 1; sc_exit(0); return 0; }

let s: i64 = sc_open();
sc_go(&child, 0);
sc_go(&child, 1);
let e: i64 = sc_close();     # 等全部结束；返回首个错误码，0 = 无
```

## 概念来源

Martin Sústrik（libdill / libmill）2016 年提出；Nathaniel Smith 在
《Notes on structured concurrency, or: Go statement considered harmful》
(2018) 里系统化成 "nursery"——协程必须有确定的所有者，所有者离开作用域
前必须 join 全部子协程，于是**并发的生命周期形状 = 代码的嵌套形状**。

形态分布（这是"概念"而不是惯例）：

| 语言 | 形态 |
|---|---|
| Python Trio / anyio | nursery，最完整的实现 |
| Kotlin / Swift | `coroutineScope` / `withTaskGroup` |
| Java | `StructuredTaskScope`（JEP 453，Java 21 预览） |
| Go | **没有** —— `go` 语句仍有协程逃逸问题，errgroup 是库级补丁 |
| C/C++ | 基本空白 |

## 为什么需要它

`csp_go()` 是"发射后不管"，子协程生命周期与调用方完全脱钩：

- 调用方读到的共享状态可能是**半成品**（没人 join）
- 一个子协程失败，兄弟还在空跑，错误也没人收到
- 父协程先退出，子协程变孤儿继续写共享内存

三条都不是崩溃，是**结果悄悄不对**。

## 三条不变量

1. **join**：scope 关闭前，所有 spawn 进来的协程必须已结束
2. **取消传播 + 错误冒泡**：任一子协程记录错误 → 兄弟被取消，错误同时
   冒泡到父 scope（外层 `close` 也拿得到）
3. **无孤儿**：close 后 `SC_LIVE` 必须为 0；**从不静默挂住**（超过
   `SC_CAPWAIT` 次就置 `SC_HANG` 并返回 -2）

## 取消是协作式的，这是刻意的

抢占式取消（直接杀协程）会让协程停在任意一条指令中间，栈与锁状态不可知。
本库与 Go `context`、Trio cancel scope 一致：取消只是置标记，由被取消方在
**取消点**检查 `sc_cancelled()` 后自行退出。

代价：阻塞在 channel 上的协程不会被唤醒。所以 `sc_recv()` 用
try + yield 轮询，而不是直接 `chan_recv()`。

## 实测（`make scopetest`，29 项）

| 场景 | 结果 |
|---|---|
| A join 之后读到完整值 | 8000（4×2000）；join **之前**是 0 |
| A close 后再等 200ms | 值不变 —— 没有协程逃逸成孤儿 |
| B 失败后兄弟收到取消 | 3/3 都收到（cseen = 0 / 0 / 16） |
| C 嵌套内层 3 个孙协程 | 全部跑完 |
| D 内层失败码 77 | **外层** close 也拿到 77 |
| E 协作式 channel | 收到全部 6 个值，FIFO 正确 |
| F 被测 scope=1，64 空体子协程 ×5 轮 | 全部 close 无错 |
| G 孙协程在内层 scope | 看到外层取消（迭代 3369），提前停 |

## 🔴 本轮两个最有价值的发现

### 一、变异脚本的备份被自己污染过，而"已还原"检查恒等

上一轮被强杀，源码停在 **M5 变异态**（`SC_LIVE[s] - 1` 变成 `- 0`）。
下一轮开工第一件事是 `cp $SRC $BK/orig.mo`——**把污染版当成了原始版**。
于是收尾的 `diff $BK/orig.mo $SRC` 两边同源，恒等，什么都验不出来。

症状极具迷惑性：之后跑出来的"基线"是 `通过 9 / 失败 14`，且 `hang != 0`
——看起来像是**结构化并发本身会偶发挂住**。实际是存活计数永远减不到 0，
`sc_close` 必然走到超时。一个真 bug 被误读成了另一个更吓人的 bug。

修法是**预习（preflight）**：在**不碰备份**的前提下，先断言源码里
5 个原始锚点各出现一次、且不含任何变异标记。不满足就报错退出，
不备份、不基线。

```bash
$ sed -i 's/- 1;/- 0;/' lib/scope.mo && bash tools/scopemut.sh
✗ 原始锚点 存活计数 缺失
✗ 源码处于 M5 变异态
  源码已被上一轮的变异污染，预习失败。不备份、不基线、直接退出。
```

> 判据必须是"源码不含变异标记"，不是"源码等于备份"。
> 当两边可能同源时，相等什么也证明不了。

### 二、向下传播是**死代码**，变异验证证明的

`sc_mark()` 里原本有一段 12 行的 O(scope) 循环，把取消标记铺给所有后代。
变异 M2 把它整个删掉，**23 项断言仍然全绿**。

原因是 `sc_cancelled()` 遍历的是**完整祖先链**：

```mo
let u: i64 = s;
while u >= 0 { if SC_CANCEL[u] == 1 { r = 1; } u = SC_PARENT[u]; }
```

而 `SC_CANCEL[s]` 在 sc_mark 开头已经置 1——任何后代的祖先链必然包含 s，
所以它们本来就看得见。**向下传播想做的事，祖先链遍历已经做完了。**

已删除（aio v1.124 删掉过同形状的一段：留着测不到又不可达的代码，
正是本项目一直在批判的形状）。

作为补偿，给真正承担这项职责的祖先链遍历补了**专属断言**（场景 G：
孙协程在内层 scope，失败发生在外层 scope，孙协程仍必须看到取消），
并把 M2 换成"不上溯祖先链"——立刻被捕获（见下表）。

## M1 未被捕获：窗口窄到 1000 次 spawn 都撞不上

"先 start 再登记"要出事，子协程必须恰好在「入队之后、`SC_CO` 登记之前」
这几十条指令内跑完。原测试里子协程体都有长循环，窗口根本撞不上。

场景 **F** 专门把窗口砸开：

- 子协程体是**空的**（上来就 `sc_exit`）
- 一次 spawn **100** 个、跑 **10 轮** = 1000 次机会
- 先开一个 dummy 占掉 scope 0，于是被测 scope 是 1——未登记的默认值
  （`sc_reset` 把 `SC_CO` 全置 -1）不会再巧合命中

**结果：仍未捕获。** 手工施加 M1 后跑 scopetest，29 项依旧全绿。

结论如实写在这里：**这条顺序约束在当前调度器下不可复现**。`csp_start`
只是入队，worker 从空队列里捞起一个协程的延迟远大于父协程那 4 次
store 的时间，父协程永远先登记完。所以 hold → 登记 → start 是
**构造上正确**的顺序，不是被实测证明必要的顺序——保留它（成本为零），
但不声称"测试证明了它有用"。

| 变异 | 结果 |
|---|---|
| M1 spawn 不 hold | ❌ **未捕获**（1000 次 spawn 未复现） |
| M2 `sc_cancelled` 不上溯祖先链 | ✅ 捕获（gseen 变 -1） |
| M3 错误不向上冒泡 | ✅ 捕获（外层拿到 0 而非 77） |
| M4 close 不 join | ✅ 捕获（sum 变 0） |
| M5 `sc_exit` 不减存活计数 | ✅ 捕获（hang != 0） |

## 已知限制

- 取消协作式：不检查取消点的协程会跑完
- 子协程必须以 `sc_exit(v)` 结束，不能用 `csp_exit()`——否则存活计数
  不减，close 会走到超时并置 `SC_HANG`（响出来，不静默挂）
- scope 数上限 32；协程槽沿用 `CSP_MAXC`（128）
- 全局 `var` 初值不接受表达式（`var X: i64 = 0 - 1;` 是语法错误），
  负初值要在函数里赋
- 必须 molink + libc

## 相关

- `lib/csp.mo`：底层协程调度器 + channel
- `lib/aio.mo`：epoll reactor，与本库的 `sc_recv` 同用
- `lib/timer.mo` + `lib/select.mo`：`tm_after` 超时进 select
- `examples/structconc.mo`：A–G 七个场景
- `tools/scopetest.sh` / `tools/scopemut.sh`
