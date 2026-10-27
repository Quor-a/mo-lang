# 泛型 trait bound（`<T: Shape>`）

```mo
interface Shape { fn area(self: ptr) -> i64; fn perim(self: ptr) -> i64; }
class Rect { w: i64; h: i64; }
fn Rect_area(self: Rect) -> i64 { return self.w * self.h; }
fn Rect_perim(self: Rect) -> i64 { return (self.w + self.h) * 2; }
impl Shape for Rect { area; perim; }

generic fn perimg<T: Shape>(a: T) -> i64 { return a.perim(); }
instantiate perimg(Rect) as perim_rect;     # ✓ Rect impl 了 Shape

generic fn tagg<T: Shape + Tag>(a: T) -> i64 { ... }   # 多 bound
generic fn pickg<T: Shape, U>(a: T, b: U) -> i64 { ... }  # 只约束其中一个
```

## 概念来源

trait bound 是泛型系统的标配约束机制：Haskell 的 type class（1989）、
Rust 的 `T: Trait`、C++20 的 `requires`、Swift 的 `where`。**墨语言此前缺的就是这个**——
泛型（v1.61）和 interface（v1.62）都有，但两者互不相干。

## 为什么需要它：名义 vs 结构

泛型原本是**结构化**匹配的：只要类型碰巧有个同名方法，instantiate 就放行。

实测（同一份 `Sneaky`，补齐了 Shape 要求的全部同名方法，但从未 `impl Shape`）：

| | 结果 |
|---|---|
| 无 bound `generic fn pg<T>` | **编译通过**，运行输出 12 |
| 有 bound `generic fn pg<T: Shape>` | **拒绝**：`Sneaky does not implement Shape` |

这不是"多了一层检查"而已，是契约性质的改变：

- **结构化**：有同名方法就算实现 —— 可能是巧合、可能签名对不上、可能是私有的辅助函数
- **名义**：显式 `impl` 才算 —— 且 impl 保证实现接口的**全部**方法，
  而泛型体可能只用其中一个。结构化匹配只保证"碰巧有这一个"

第二条是独立理由：`impl` 检查的是"接口要求的方法全都实现了"，
结构化匹配连这个都管不到。

## 实现：检查必须推迟到解析结束

`impl` 可能出现在 `instantiate` **之后**（前向引用）。若在 instantiate 处立即检查，
`K_NVT` 还没填完 → 误报。所以只登记待检查项，在 `iface_patch_vtables()` 之后统一查
—— 与 vtable 回填是同一个道理。

实测：impl 写在 instantiate 之后，编译通过并输出正确值。

三块新增静态区（都算过边界，相邻区域分别是 O_FILES=12582912 与 O_GENBUF=89000000）：

| 区域 | 内容 |
|---|---|
| `O_VTK` / `O_VTT` | impl 对应的 interface 索引与**类型名** |
| `O_GBC` / `O_GBB` | 每个类型参数的 bound 个数与 interface 索引 |
| `O_BCI/BCL/BCC/BCT` | 待检查项：接口、行列、类型名 |

## 🔴 四个坑

**1. `make sync` 是从分片**拼接**覆盖 `src/compiler.mo`。**

本轮第一轮我直接在 `src/compiler.mo` 上改完，顺手 `make sync` —— 改动被**静默还原**，
`grep` 自己的新代码返回 0 才发现。Makefile 里那条 `sync-check` 的提示写得清清楚楚：
*"改编译器要改 `src/mo/` 下的片段，然后 `make sync` 重新拼接"*。
这是文档明写、守护明在，仍然犯了一次。

**2. 移动 `nt = nt + 1` 时残留了一个多余的 `next_token()`。**

类型参数列表里"读完名字立刻推进"只有一次是对的。多推进一次就把 `>` 跳过去，
症状是在函数体的 `(` 上报 `syntax error` —— 位置离真正的改动有十几列，
而且**无 bound 的路径也一起挂了**（回归），第一次二分才定位到。

**3. 类型名必须拷出共享区。**

`impl` 的类型名在 `O_SCAL + 1792`（共享临时区），instantiate 的实参在 `O_GAB`。
两者都会被下一次解析覆盖，所以登记时一律 `memcpy` 进专用缓冲。
本项目已第 N 次栽在"共享临时被下一次调用抹掉"上，这次是设计时就规避的。

**4. 方法真的缺失时，bound 轮不到报错。**

`no such method` 在展开时立即报出，早于 bound 检查。所以"缺方法"和"没 impl"
是两种不同的失败，测试里必须分开构造 —— 想测到 bound，类型必须**有**那个方法。

## 验证

`make tbtest` 11 项：正例 6 项断言、无 bound 对照（必须放行）、三个负例、回归。
`make tbmut` 四个变异全部被捕获：

| 变异 | 变红 |
|---|---|
| M1 bound 检查永不拒绝 | 4 项 |
| M2 恒判定为已 impl | 4 项 |
| M3 不记录 bound 个数 | 4 项 |
| M5 impl 全记成 interface 0（**误拒**方向） | **1 项** |

M5 是必要的：只测"该拒的拒了"，分不清"检查生效"和"见谁都拒"。
但 M5 只红 1 项，**冗余度低**——改这两处附近时应先补断言。

## 已知限制

- 每个类型参数最多 4 个 bound，待检查项最多 64 条（超限明确报错）
- bound 只做**存在性**检查，不校验方法签名是否一致（接口声明里方法签名不参与匹配）
- 同一接口对同一类型重复 `impl` 不报错（后写覆盖），这是既有行为，未在本次收紧
- 不支持 `where` 子句形式，只支持 `<T: A + B>`
- bound 不影响代码生成：单态化后仍是直接调用，没有 vtable 开销
