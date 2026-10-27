# ioto.mo —— 带超时的异步 I/O

## 它是什么

把「I/O 就绪」和「超时」**都做成 channel**，然后一个 select 二选一：

```mo
sel_case(ioch, 1, 0);
sel_case(tm_after(ms), 1, 0);
k = sel_go(0);          # 0 = 就绪，1 = 超时
```

这正是 Go 的 `select { case <-ch: case <-time.After(d): }`，
也是 RFC 793 以来每个网络程序都需要的东西：**读超时**。

形态分布：Go 是 netpoller + time.After（语言级）；Rust 是
`tokio::time::timeout(...)`（库级）；C/C++ 靠 libuv / asio 的
deadline_timer，裸 epoll 要自己算。墨语言这边是
reactor（`lib/aio.mo`）+ 时间轮（`lib/timer.mo`）+ select（`lib/select.mo`）
三块拼起来的。

## 🔴 为什么必须能取消

两个分支只有一个会赢，**赢的那个必须把输的取消**：

| 谁赢 | 不取消的后果 |
|---|---|
| I/O 先就绪 | 定时器到期后往一个即将被别人复用的 channel 投递 → **下一个请求一上来就"超时"** |
| 超时先到 | fd 还留在 epoll 里、槽还占着 → fd 号复用后收到别人的事件 |

第一条就是**幽灵超时**。它只在特定时序下发作，绝大多数请求完全正常。

实测（变异 M1：把 `tm_cancel(t)` 换成 `tm_cancel(-1)`）：

```
基线   通过 21 / 失败 0   cncl=6  fired=6  nto=6
变异   通过 17 / 失败 4   cncl=0  fired=12 nto=6    ← 第一次跑
变异   通过 17 / 失败 4   cncl=0  fired=12 nto=8    ← 另一次跑
```

第二次跑 `nto` 从 6 变成 8 —— **两个正常请求被幽灵超时误掐断了**。
而第一次跑没有。这正是它的形状：**偶发，不是必然**。

`fired=6` 而不是 12 是取消生效的硬证据：12 次 arm 里 6 次被拦住。

## 取消怎么做到 O(1)

时间轮相对堆的真正优势就在这里（Go 用四叉堆，取消要 O(n) 查或惰性删除）。
前提是链表**双向** —— 所以 `lib/timer.mo` 加了 `TM_PRV[]`：

| | 插入 | 取消 |
|---|---|---|
| 排序数组 | O(n) | O(n) |
| 四叉堆 | O(log n) | O(n) 查 / 惰性 |
| 时间轮 | **O(1)** | **O(1)** |

handle 是 `槽号 + 世代×1024`，存在 `TM_OF[channel]` 反查表里，
所以 `tm_cancel(c)` 直接拿 channel 号定位，不需要额外句柄、不需要指针参数。
槽号会复用，世代让"取消一个早已触发的定时器"变成可判定的：
世代不符 → 返回 1（迟了一步），不会误摘别人的槽。

## 竞态：投递必须在锁内

`tm_tick` 里的 `chan_trysend` **不能**移到锁外。放到锁外的话，
`tm_cancel` 可能在「已摘链但还没 send」之间抢到锁，判定"已触发"于是把
channel 归还池，紧接着这次 send 落进一个已被别人复用的 channel。

`aio_fire` 里的 `chan_trysend` 同理（M2 变异就是去掉 `aio_disarm`）。

## 实测（`make iototest`，21 项）

`examples/httpto.mo`：6 个快客户端（连上立刻发）+ 6 个慢客户端
（连上后睡 3 秒不发），服务端用 `ioto_recv(fd, buf, 1023, 400)` 读。

```
nconn=12 nok=6 nto=6 toms=407 cncl=6 late=6 tdrn=0 idrn=0
fired=6 miss=0 iok=6 ito=6 iovf=0 aion=1 chnc=17
```

| 数字 | 含义 |
|---|---|
| `nok=6` / `nto=6` | 快的全响应、慢的全被掐断 |
| `toms=407` | 超时实测 407ms（deadline 400，误差 ≤ tick） |
| `cncl=6` | I/O 就绪分支成功取消 6 个定时器 |
| `fired=6` | 12 次 arm 只有 6 次真正触发 |
| `late=6` | 超时分支的 cancel 迟了一步（已触发） |
| `tdrn=0` / `idrn=0` | 没有残留值（幽灵的证据） |
| `aion=1` | 只剩 acceptor 的监听 fd；业务 fd 槽全清 |
| `chnc=17` | channel 总数有界（回收池生效） |

## 两个坑

**`write()` 只有 3 个参数。** 想用 `MSG_NOSIGNAL` 避开 SIGPIPE 必须走
`sendto`（syscall 44）—— 写成 `syscall(1, fd, buf, n, 0x4000, 0, 0)` 时
第 4 个参数被忽略，慢客户端在已关闭的连接上 send 会直接把进程杀掉
（退出码 141），看着像"程序崩了"。

**快客户端也必须分两次发。** 第一版快客户端一次发完，服务端第一次
`read` 就拿到全部，`TM_CNCL` 恒为 0 —— 取消有没有生效**根本看不出来**。
后来让客户端发完请求行睡 120ms 再发空行，才逼出「等待 → 取消」这条路径。
另外 worker 数要 ≥ 快客户端数，否则后几个连接会排队，等轮到它们时
数据已经齐全，又变成不等待了（实测 `NWORKER=4` 时 `cncl` 只有 4）。

## 变异验证（`make iotomut`）

| 变异 | 结果 |
|---|---|
| M1 不取消定时器 | ✅ 3~4 项变红（cncl 0、fired 12） |
| M2 等待的事件方向写反（读等成写） | ✅ 4 项变红（cncl 爆到 7025 —— 写事件永远就绪） |
| M4 channel 用不回收 | ✅ 8 项变红（chnc 突破上限） |
| M3 不排空 channel | ❌ **未捕获**（记录性） |
| M5 不注销 fd | ❌ **未捕获**（记录性） |

**M3 未捕获**不是"这条检查没必要"：在当前负载下 channel 归还时本来就是
空的（只有两个 case 同时命中、只取走一个才会残留），排空是防御性冗余。

**M5 未捕获**也是有原因的：`aio_close()` 里本来就会清槽，所以当前调用
模式下 `aio_disarm` 是第二道保险。留着这两个记录性变异，是因为
"改了代码却没变红"本身也是信息，不该被悄悄删掉。

**被换掉的 M4**（超时当成 I/O 就绪）同样不被捕获，原因很清楚：
`ioto_recv` 会在 `rem <= 0` 时兜住并最终返回超时，行为等价 —— 那不是缺陷。
换成"池不回收"之后立刻挂 8 项。

## 已知限制

- 超时精度 = 时间轮 tick（16ms）
- I/O channel 池 32 个；并发 I/O 超了返回 -3 并置 `IOTO_OVF`（响出来，不静默退化）
- 一个 fd 同时只能有一个等待者（继承自 aio.mo）
- `ms <= 0` 表示**无限等待**（退化为不带超时的 `aio_*`）
- 必须 molink + libc

## 用法

```bash
make iototest      # 21 项端到端断言
make iotomut       # 4 个变异验证
```
