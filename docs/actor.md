# Actor 模型 + 监督树（`lib/actor.mo`）

```mo
let sup: i64 = sup_new(STRAT_ONE, 5, 1000);   # 策略 / 强度 / 窗口(ms)
let p0: i64 = sup_addch(sup, &worker, 0);
sup_start(sup);
act_send(p0, 1);
```

## 概念来源

Hewitt（1973）提出 Actor；Erlang/OTP 把它工程化，核心是两条：

- **shared nothing**：状态私有、邮箱串行、消息异步，因此**不需要锁**
- **let it crash**：出错不就地处理，而是崩溃、由**监督者**决定怎么办

监督树（supervisor tree）是 OTP 的容错结构：重启策略 + 重启强度
（intensity / period）—— 窗口内重启超限 → **监督者自己崩**，错误继续
向上冒。一个系统会"逐级放弃"，而不是无限重启。

形态分布上这是"概念"不是惯例：Erlang/OTP、Akka、CAF 有；
**Go 没有**（errgroup 只覆盖"等待 + 首个错误"，不重启）；
Rust 无内建。

## 与 `lib/scope.mo`（nursery）是相反的两条哲学

| | 错误去向 | 父做什么 |
|---|---|---|
| nursery（scope.mo） | 冒泡到父 | **等待并传播，不重启**；子不许活过父 |
| supervisor（actor.mo） | 冒泡到父 | **隔离并重启**；子崩溃是正常路径 |

一个"终止"，一个"重启"。放在一起才看得清取舍。

## 三条不变量

1. 状态私有：actor 的状态只有它自己写，因此不需要锁
2. 邮箱串行：一个 actor = 一个协程，消息一条一条处理，永不重入
3. 重启 = 重建：`ACT_GEN` 递增、`ACT_MSGN` 归零 —— 这是可观测后果

## 判据：三个策略必须给出三个不同的重启集合

| 策略 | gen | msgn |
|---|---|---|
| one-for-one（只重启失败者） | `[0,1,0]` | `[60,0,60]` |
| one-for-all（重启全部） | `[1,1,1]` | `[0,0,0]` |
| rest-for-one（失败者及其之后） | `[0,1,1]` | `[60,0,0]` |

只看"有没有崩"分辨不出这三者——它们都会安静地跑完。

## 🔴 本库此前从未被验证过，一验证就发现两个策略完全不工作

`lib/actor.mo` 与 `examples/supertree.mo` 存在于仓库、能编译、跑起来
退出码 0、打印的数字看起来也合理。**但 one-for-one 与 rest-for-one
两个策略根本没有重启过任何 actor。**

根因是 `sup_waitdead` 的**等待集合与重启区间不一致**：

```mo
let lo = idx; let hi = idx + 1;              # one-for-one：只停失败者
while i < hi { act_send(p, ACT_STOPV); }     # 只停区间内的
...
sup_waitdead(sup, 20000);                    # 🔴 却等**全部** children 死
```

区间外的 children 永远活着 → 必然超时 → `return -1` → **一个都不重启**。

> 症状是完全静默的：不报错、崩溃不算失败、示例退出码 0，`gen` / `msgn`
> 就保持"没重启过"的样子。只有把三个策略的期望值都写出来比对才发现。
> 而且它有个残留痕迹：超时会置 `ACT_SFAIL[sup]=2` 并 `ACT_SFAILN+1`——
> 实测 `sfailn=3`（预期只有 1 次强度超限），多出的两次就是它。

修法是让 `sup_waitdead` 只等 `[lo,hi)`。修复后三个策略立刻给出三个
不同的重启集合，`sfailn` 从 3 降到 1。

**这个库此前没有任何测试引用，是 `make check` 第 3 项报红才发现的。**
存在于仓库 ≠ 被验证过。

## 诊断决策：把「决策本身」记下来

`ACT_DIAG[0..5]` 记录最后一次重启决策的
`[策略, idx, lo, hi, cpid, children数]`。

排查时最先要区分的就是"区间算错了"和"区间对但重启没生效"——
实测三个场景的 `lo/hi` **全是对的**，正是这条诊断把怀疑从"策略分支写错"
引到了 `sup_waitdead`，否则很容易在错误方向上改半天。

## 验证：`make actortest`（37 项）

三个策略各 6 项断言（gen + msgn）、三个集合两两不同、
重启强度（窗口内 vs 窗口过期）、become、以及诊断计数器必须为 0。

其中 `sfailn=1` 那条专门盯着上面那个缺陷——它若复发，这条立刻变红。

## 已知限制

- 最多 32 个 actor、8 个 supervisor（`ACT_*` 数组定长）
- 消息是单个 i64，无结构化 payload
- 邮箱容量 64，满了发送失败（置 `ACT_SENDERR`，不静默丢）
- 重启强度窗口用 `clock_ms()`，窗口 < 2×tick 时可能判不准
- 非分布式：只在单进程内（真 OTP 的 actor 可跨节点）
