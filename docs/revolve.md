# Revolve 最优 checkpointing（1.83）

## 概念来源

Griewank, A. & Walther, A. (2000) "Algorithm 799: revolve: an implementation of
checkpointing for the reverse or adjoint mode of computational differentiation",
ACM TOMS 26(1), 19–45.

给定 `l` 步前向与 `c` 个快照，求**重算次数最少**的反向调度。

**它还躺在 PDF 里的程度**：主流深度学习框架（PyTorch / JAX）都没有内建；
只有科学计算侧有实现——Firedrake 的 `checkpoint_schedules`（`MultistageCheckpointSchedule`
明确注明 "The standard revolve solution, as specified in the equation at the bottom
of p. 34 of GW2000"）、PETSc 的 `TSTrajectory`、dolfin-adjoint。
也就是说：这篇 2000 年的算法，25 年后仍是少数人才用得上的东西。

## 🔴 先纠正 1.82 的一个错误说法

1.82 我说"PyTorch 只用均匀分段，白白多算 30~40%"——**这个说法是错的**。

在「各步激活大小相同 + **重算时能保留段内中间值**」的假设下，均匀分段
在内存角度就是最优的，且重算代价**恒为一次完整前向**，与段数无关：

> 每段重算一次，共 K 段，每段 n/K 层 ⇒ 总重算 = K·(n/K) = n

实测（本仓库 `tests/110_revolve.mo`，tape 17 步）：

```
均匀分段 + 段内保留（PyTorch 模型）
  k=2..5   重算 = 17     ← 恒等于一次完整前向
```

**所以 PyTorch 不需要 Revolve 是对的，不是偷懒。**

Revolve 的真正适用场景是**内存更紧**的模型：

| 模型 | 内存 | 重算 |
|---|---|---|
| 存全部中间值 | O(l) | 0 |
| 均匀分段 + 段内保留（PyTorch） | O(l/k) | l（恒定） |
| **均匀分段 + 逐层（Revolve 的模型）** | **O(c) + 1 个当前状态** | 见下 |

在 Revolve 的模型里，**重算时走过就覆盖，不保留段内历史**——内存只够
`c` 个状态快照加一个当前状态。这才是它最优的那块地盘。

## 实测对比（tape = 17 步）

| 快照槽 c | Revolve | 均匀逐层（同槽数，k=c+1） | 节省 |
|---|---|---|---|
| 0 | 136 | — | — |
| 1 | 50 | 64 | 22% |
| 2 | 31 | 40 | 23% |
| 3 | 22 | 28 | 21% |

每组梯度与不 checkpoint 的完整反向**逐值一致**（`不一致 = 0`）。

## 模型与递归式

```
σ_t      = 执行完 tape 前 t 步之后的所有 AD_VAL
反向第 t 步（tape[t-1]）需要 σ_{t-1}

cost(1, c) = 0
cost(m, 0) = m(m-1)/2                  # 逐个从段首重算
cost(m, c) = min_{1<=k<m} [ k + cost(m-k, c-1) + cost(k, c) ]
                            ^   ^^^^^^^^^^^^^^^   ^^^^^^^^^^
                  建快照的 k 步  右半（占 1 槽）   左半（槽已归还，仍有 c 个）
```

最后一项是 Revolve 的关键：**右半做完后切点的槽被释放，左半仍持有全部 c 个槽**。

## 🔴 修过一个真实的建模错误（实测暴露，不是推测）

第一版 `c=3` 时 Revolve 重算 **30** 步，反而**多于**同槽数均匀分段的 28 步。
最优算法不该输给它的特例，所以是模型错了。

根因：**初始前向 l 步本来就要走完**（否则算不出 loss），途中顺手存快照是
**免费**的。原递归把第一次建快照的 k 步也计成重算，于是
"平铺 c 个快照、每段逐层"这个候选根本不在搜索空间里。

修正：顶层允许平铺 `j` 个免费快照（`0 <= j <= c`），分成 `j+1` 段，段内递归
仍可用剩下的 `c-j` 个槽。`j=c` 时退化为均匀分段，所以**新实现不劣于均匀分段**
——这条已经写成测试里的硬断言：

```mo
ad_backward_uniform_tight(l, c + 1);   # 同槽数的均匀分段
if rc > rcu { fail = fail + 1; }       # Revolve 不得更多
```

变异验证：把顶层的 `return bj` 改成 `return 0`（退化成纯嵌套），
`fail` 从 0 变 3 —— 断言确实在起作用。

## 自洽检验

DP 预测的代价与实际执行的重算步数逐档比较：

```
c=0  重算=136  DP=136
c=1  重算=50   DP=50
c=2  重算=31   DP=31
c=3  重算=22   DP=22
```

执行与模型完全吻合。

## 接口

```mo
ad_backward_revolve(loss, c)            # Revolve 调度反向
ad_backward_uniform(loss, k)            # 均匀分段 + 段内保留（PyTorch 模型）
ad_backward_uniform_tight(loss, k)      # 均匀分段 + 段内逐层（同一内存模型）
ad_recompute_count()                    # 重算步数
ad_reverse_count()                      # 反向步数
ad_ckpt_err()                           # 0=ok 1=不支持 2=槽耗尽 3=超限 4=快照缺失
ad_rev_topcost(m, c)                    # DP 预测代价
```

## 坑

1. **顶层快照的计费**——见上，是最难发现的一个：它不报错，
   只是让"最优"算法输给它自己的特例。是靠**同时跑一个 baseline 对比**才发现的。
2. **`OP_VADD_B` 的偏置按通道 `i` 索引**，不是元素 `j`。与 1.80 同一个坑，
   写成 `b + j` 会静默读到别的通道。
3. **DP memo 用 `cost+1` 存储**，用 0 表示"未计算"——否则 `cost=0` 与未计算无法区分。
4. **不支持重算的算子明确报错**（`AD_CKERR=1`）：conv / pool / gmax / gavg / sce /
   mmba / mbat。绝不静默跳过——1.39 的 `ad_set` 事件就是被静默当 0 坑的。

## 限制

- 只支持能"重算值"的算子子集（标量运算、matmul、块级激活、mse/mseh）
- `AD_CKMAX = 6` 个快照槽，tape 超过 255 步报 `err=3`
- 每个快照保存全部 `AD_N` 个槽（最多 2048），不是增量
