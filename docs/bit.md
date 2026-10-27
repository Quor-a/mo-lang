# bit —— Fenwick 树 / Binary Indexed Tree（早期实现）

`lib/bit.mo` · 测试 `tests/150_bit.mo`（30 项断言）· 变异 `tools/bitmut.sh`

## 概念来源

Peter M. Fenwick 1994，《A New Data Structure for Cumulative Frequency Tables》。
核心恒等式：把下标 i 的最低置位记作 `lowbit(i) = i & (−i)`，则

- 前缀和 `sum(1..i)`：从 i 开始每次**减** lowbit(j) 累加
- 单点加 `add(i, d)`：从 i 开始每次**加** lowbit(j) 上去

两条路径互为逆运算，于是"改一个数"和"问一段和"都是 O(log n)，而
**结构本身只是一个平铺的数组** —— 没有指针、没有节点、没有旋转。

## 与 `lib/fenw.mo`（v1.148）的关系：两份并存，互为独立参照

项目里现有**两份** Fenwick 实现，这是事实，不是疏漏：

| | `bit.mo`（本文件，早期） | `fenw.mo`（v1.148） |
|---|---|---|
| 形态 | 单点加 + 前缀和 / 区间和 | 四种形态，含区间加 + 区间和 |
| 独有 | `bit_merge` / `bit_sub` / `bit_diff` / `bit_build` | `fw_lower`（二进制提升） |
| 测试 | `tests/150_bit.mo` | `tests/150_fenw.mo` |

两份都保留，遵循本项目的惯例：**独立参照不删除**。两份实现走不同的
代码路径，对同一组输入给出一致结论时，才说明结论可信；只留一份的话，
"一致"只是"同一个 bug 算了两次"。

⚠️ 已知欠账：两份实现的**接口命名不统一**（`bit_*` vs `fw_*`），
且功能有交叉重叠。合并或明确分工尚未做 —— 在此之前，新代码请优先用
`fenw.mo`（形态更全、有结构性断言），`bit.mo` 仅当需要 `merge/sub/diff` 时才用。

## 已知限制

- 下标 1-based；越界行为由各函数自行返回 -1
- 池式分配，容量固定
- `bit_merge` 要求两棵树 n 相同，否则返回 -1
