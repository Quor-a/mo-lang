# Multistage 两级 checkpointing（1.84）

## 概念来源

Stumm, P. & Walther, A. (2009) "Multistage approaches for optimal offline
checkpointing", SIAM Journal on Scientific Computing 31(3), 1946–1967.

Revolve（1.83）假设所有快照**同质**（同成本、同层级）。真实机器有 RAM 与磁盘
两级：磁盘容量不限，但一次 IO 贵得多。Multistage 把快照分配到两级，最小化
「重算 + IO」的总代价。

**它还躺在 PDF 里的程度**：只有 Firedrake 的 `checkpoint_schedules` 有实现
（`MultistageCheckpointSchedule`、`TwoLevelCheckpointSchedule`，文档明确注明
"Uses a MultiStage distribution of checkpoints between RAM and disk"）。
PyTorch / JAX 没有两级调度——它们连一级的 Revolve 都没有。

## 统一模型

把 `l` 步切成 `N` 段，段起点 `BK[0..N-1]`（`BK[0] = 0`）：

| 起点 | 存哪 | 代价 |
|---|---|---|
| `BK[0..j]`（前 j+1 个） | **RAM** 槽 0..j | 主前向中顺手，**免费** |
| `BK[j+1..N-1]` | **磁盘** | 每次写 + 读 = `2w` |

段内用剩下的 `r-j` 个 RAM 槽做 Revolve 递归。

```
RAM 状态数 = (j+1) + (r-j) = r + 1      ← 恒定，与纯 RAM Revolve 相同

disks = 0                  若 N-1 <= j（起点全在 RAM，不需要磁盘）
      = N - j              否则（含 σ_0 的一份磁盘副本）

T(N,j) = disks·2w + Σ_{i=1..N} cost(seg_i, r-j)
```

**`j = N-1` 时 `disks = 0`，恰好退化为 1.83 的纯 RAM Revolve。**
所以纯 RAM 解**在搜索空间内**，Multistage 的最优值必然 ≤ 它——
这是测试里写死的硬断言，不是期望值。

## 实测（tape 17 步，r = 2 即 3 个 RAM 状态）

| w | N | j | 重算 | IO | Multistage 总代价 | 纯 RAM Revolve |
|---|---|---|---|---|---|---|
| 1 | 6 | 1 | 11 | 10 | **21** | 31 |
| 2 | 3 | 1 | 22 | 4 | **30** | 31 |
| 4 | 2 | 1 | 31 | 0 | 31 | 31 |
| ≥8 | 2 | 1 | 31 | 0 | 31 | 31 |

- 磁盘便宜（w=1）时，Multistage 用磁盘换来"段内保留更多 RAM 槽"，
  **总代价 21 vs 31，省 32%**
- 磁盘昂贵（w≥4）时，自动退化为纯 RAM 方案（IO=0），代价与 Revolve 持平
- 所有 w 下梯度与完整反向**逐值一致**（`不一致 = 0`）

## 权衡的本质

不是"磁盘比 RAM 便宜"，而是：

- **纯 RAM Revolve**：用 j 个 RAM 槽做顶层平铺，段内只剩 `r-j` 个槽
- **Multistage**：用磁盘做顶层平铺（不占 RAM），段内保留**全部 r 个槽**

磁盘换来的是"段内多 j 个槽"。所以 w 小时 Multistage 胜，w 大时纯 RAM 胜。
这不是近似，是同一个搜索空间里的两个角点。

## 磁盘是真的磁盘

`ad_disk_save` / `ad_disk_load` 用 `fs.mo` 的 `fopen/fwrite/fread` 真写文件，
不是模拟。测试里先把 `AD_VAL` 全部改成 `-999` 再 load，确认真的覆盖回来：

```
写=1  读=1  不一致=0   ✓ 往返一致
```

## 验证

1. **磁盘往返**：save → 破坏 → load，逐槽一致
2. **正确性**：每个 w 下梯度与完整反向逐值一致
3. **最优性**：`Multistage 总代价 ≤ 纯 RAM Revolve`（同 RAM 状态数）
4. **退化**：w 极大时 IO=0 且重算等于纯 Revolve
5. **启用**：w 小时 IO>0（确实用上了磁盘）

变异验证：把搜索限制成"只允许纯 RAM 解"（`n <= r+1, j = n-1`），
`fail` 从 0 变 1（"w 小时应用上磁盘"被抓出）——断言确实在起作用。

## 接口

```mo
ad_backward_multistage(loss, r, w)   # 两级调度反向
ad_ms_time(l, r, w)                  # DP 预测总代价
ad_ms_cost(l, r, n, j, w)            # 指定 (N,j) 的代价
ad_ms_n() / ad_ms_j()                # 选中的段数 / RAM 起点数-1
ad_ms_dw() / ad_ms_dr() / ad_ms_io() # 磁盘写 / 读 / 合计次数
```

## 坑

1. **σ_0 需要一份磁盘副本**（当 `N>1` 且用到磁盘时）。反向最后一段是段 1，
   起点 σ_0 在 RAM 槽 0 —— 但槽 0 在前面的段里已被磁盘恢复的数据覆盖。
   不另存一份就会读到错误状态，而**梯度依然算得出来**，只是错的值。
2. **段内不能做 RAM 平铺**。顶层平铺之所以免费，是因为主前向本来就要走完
   全程；段内平铺发生在反向阶段，重算是真代价。所以平铺只出现在顶层。
3. `byte` 数组声明必须带初值（`var CKPATH: [64] byte = 0;`），
   否则报 syntax error 指向 `byte` 那一列。
4. 测试里 `ad_recompute_count()` 必须**立即**取：后面再跑
   `ad_backward_revolve` 会把 `AD_RC` 覆盖掉。第一版就是这样，
   于是所有 w 都打印出同一个 31，像是"重算与 w 无关"。

## 限制

- `AD_CKMAX = 6`，故 `r ≤ 5`；tape 超 255 步报错
- 磁盘快照每个写全部 `AD_N` 个槽（最多 2048），不是增量
- 代价用**计数模型**（IO 次数 × w），不是真实计时——
  真实计时在定点小 workload 上噪声大于效应（1.79 的教训）
