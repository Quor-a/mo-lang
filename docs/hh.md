# Heavy Hitters —— Misra-Gries + Space-Saving

`lib/hh.mo` · 测试 `tests/152_hh.mo`（45 项） · 端到端 `make hhtest` · 变异 `make hhmut`

## 概念来源

- **Misra-Gries**：Jayadev Misra, David Gries 1982《Finding Repeated Elements》
  引理 3 的"减一"算法。现代称谓 Misra-Gries / "Frequent"
  （Cormode-Hadjieleftheriou 2008 的综述给了标准形式）。
- **Space-Saving**：Ahmed Metwally, Divyakant Agrawal, Amr El Abbadi 2005
  《Efficient Computation of Frequent and Top-k Elements in Data Streams》。

**五个都没进任何主流语言的标准库** —— Bloom(v1.144)、CMS(v1.144)、
HLL(v1.138)、qdigest(v1.147)、hh(v1.150)。Python 靠 datasketch、
Java 靠 stream-lib、Go 靠第三方包。

## 它在这一组里的位置

| 草图 | 回答 | 误差方向 |
|---|---|---|
| Bloom | 在不在 | 只假阳 |
| CMS | 出现几次 | 只高估 |
| HLL | 几个不同的 | ±相对误差 1.04/√m |
| qdigest | 排第 q 是几 | 秩误差与 k 同阶 |
| **hh** | **谁最频繁** | **MG 低估 / SS 高估** |

### 最要紧的一条：本库**确定性，不用哈希**

Bloom / CMS / HLL 的误差都依赖哈希质量（本项目在 HLL v1.138 就栽在
`a ^ sar(a,k)` 的 bit63 恒为 0 上，症状是"只用了一半桶"却完全看不出来）。

**Misra-Gries 与 Space-Saving 完全不用哈希。** 它们的误差只来自计数器
数量 k，是确定性算法，所以误差界是**硬保证**而非概率：

- MG：`est(x) ≤ true(x) ≤ est(x) + D`，且 `D ≤ N/k`
- SS：`est(x) − err(x) ≤ true(x) ≤ est(x)`，err 由替换过程记录

### 两个算法方向相反 ⟹ 可以**夹逼真值**

```
mg_est(x) ≤ true(x) ≤ ss_est(x)
```

这是本测试最硬的判据。MG 是这一组草图里**唯一给下界**的，SS 给上界
（CMS 与 SS 同侧，也是高估）。任一侧写错方向，夹逼立刻挂 ——
而单看任何一侧"est 落在某个区间内"都可以靠放大区间混过去。

## 实测（`make hhtest`，N=4000，k=64）

```
N=4000 k=64 Noverk=62 mg_dec=51 mg_used=29 ss_used=64 ss_min=52
ss_repl=2325 seen=857 inMG=29 inSS=64 bracket=64

clamp[1] mg=349 true=400 ss=400 sserr=0
clamp[2] mg=149 true=200 ss=200 sserr=0
clamp[3] mg= 49 true=100 ss=100 sserr=0
```

| 量 | 实测 | 说明 |
|---|---|---|
| `mg_dec` | 51 | ≤ N/k = 62，硬保证成立 |
| `mg_used` | 29 | **< k** —— 减量真的清过槽（SS 是 64 = 满，永不减员） |
| `ss_min` | 52 | SS 误差上界 |
| `ss_repl` | 2325 | 替换次数（非空转守卫） |
| `seen` / `inMG` / `inSS` | 857 / 29 / 64 | 857 个不同值只留 29~64 个槽 |
| `bracket` | 64 | 被夹逼的元素数 |

### 🔴 一个可以钉成**等号**的精确定量

重击者从未被逐出 ⟹ 每次减量它都跟着减 1 ⟹

```
est(x) == true(x) − D      （不多不少）
```

实测三个重击者的低估量**都是 51**，与 `mg_dec=51` 完全一致：
`400−349` / `200−149` / `100−49`。

这比"est ≤ true ≤ est+D"强得多：**界只给范围，这条给等号**。
已写成断言（`A: 重击者 N 低估量 == D`）。

同理，从未被替换过的 SS 槽是**精确**的：`ss_est == true` 且 `ss_err == 0`
（SS 的误差全部来自"被吸收"的那部分，重击者没被吸收过）。

## `ss_est` 不在表中返回 −1，不是 0

返回 0 会让人误读成"它出现了 0 次"，那是**假阴**。SS 对被逐出的元素
**没有估计**，必须区分"估计为 0"和"不知道"。

MG 那边返回 0 是对的 —— MG 给的是下界，0 恒为合法下界。

## 变异验证 `make hhmut`：7 / 7 被捕获

| 变异 | 破坏的东西 | 变红 |
|---|---|---|
| M1 `mg_est` 不在表返回 D | MG 下界 | 1 |
| M2 减量时不真减 | MG 下界（计数只增不减） | 2 |
| M3 SS 新 count = c | SS 上界 | 1 |
| M4 SS `err = 0` | err 界的依据 | 58 |
| M5 MG 满时直接丢弃、不减量 | 不漏保证（D 恒 0） | 1590 |
| M6 `ss_est` 不在表返回 0 | 假阴伪装成 0 | 3 |
| M7 SS 替换**最大**的 | 不漏（重击者被踢） | 4 |

**M1 / M3 只挂 1 项，但不是冗余度薄** —— 那 1 条是**聚合守卫**
（`A: MG 下界全覆盖`：got 29, want 857）。它背后是 857 个元素的逐条核对，
一条聚合断言比 800 条独立断言更不易被数量淹没。

## 🔴 我自己在本轮犯的两个错

**一、`test_done(); return 0;`** —— 吞掉失败数，退出码恒 0。
这正是 v1.115 修过、之后又反复强调的模式，我在新测试里**原样犯了一次**。
第一次运行时 40 项里 1 项失败，RC 却是 0，`make test` 会照旧报通过。
改成 `return test_done();` 才暴露出来。

**二、把 SS 的性质套到 MG 上。** 第一版断言 `mg_used() == HH_K`，
实测 got 29。那**不是缺陷** —— SS 的替换是"换人"所以永不减员、恒满；
MG 的减量会清槽，所以只满过、不恒满。是断言写错了。
已改成上界 + 非空 + `mg_used() < HH_K`（后一条反过来证明减量真的清过槽）。

## 已知限制（都没静默）

- 容量 `HH_K` 上限 64（数组固定），`HH_K` 可在运行时调小
- 只支持**加权插入**，不支持删除 —— 删除会破坏两个算法的误差界，
  不是在现有结构上加个减法就行的
- `ss_min()` 每次线性扫描 O(k)，热路径应缓存
- 查找是 O(k) 线性扫描；要 O(1) 得加一层哈希索引（那会把"不用哈希"
  这个性质丢掉，是明确取舍，不是没做）
- 只给候选集与估计，**不做排序**（取 top-k 要调用方自己排）
- `hh_add` 的 `c ≤ 0` 返回 −1 并置 `HHBAD`，不静默忽略

## 调用方禁令

`HH1..HH4 / HHF1 / HHA1 / HHA2 / HHQ1 / HHM1` 是本库内部的循环与临时变量。
**调用方绝不能拿它们当自己的循环变量** —— 一次 `hh_add` 就改掉它们，
外层循环当场退出，症状是"只加了一个元素"，**不报错**。

本项目已在 HDC(v1.108)、SDM(v1.110)、LSH(v1.137)、HLL(v1.138)、
CMS(v1.144)、qdigest(v1.147)、seg(v1.149) 栽过同一类跟头。
