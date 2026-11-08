# v1.1154: 全局 enum 变量

## 背景

带数据变体的 enum（`enum Sh { Circle(i64); Square(i64); }`）此前只支持
**形参**（v1.1057/v1.1153）与**局部 let** 的类型注解，全局 `var g: Sh;`
无法声明 —— `Sh` 不在 struct 表，`parse_global` 把 `Sh` 当未知类型，
落到数组分支报错；即使绕过，`g = Sh.Circle(5);` 赋值也因
`ty_compat(ty_int, ty_struct)` 拒绝（右侧 enum 构造 R_ETY 是 variant struct）。

## 修复

### 1. `parse_global` 识别 enum 名

`var g: Sh;` 声明时，`enum_type_exists("Sh")` 命中 → 登记为 i64 全局槽
（数据段 8 字节），与局部 enum 变量一致的**地址语义**（槽内存 variant
对象地址，match 变体臂解引用取数据）。

### 2. 赋值特判

`g = Sh.Circle(5);` 是赋值语句，走 `parse_expr` 的 `=` 处理。左侧 `g`
类型 i64，右侧 R_ETY 是 variant struct（名含 `$`）且 R_SADDR=1（rax=对象
地址）。在 `ty_compat` 拒绝前加特判：右侧是 enum 变体构造时，允许把
地址直接存入标量槽（`store_sym`），语义与局部 `let s: Sh = Sh.Circle(5)`
完全一致。

## 设计说明

- enum 变量（全局/局部）采用**地址语义**：槽内存 variant 对象地址，
  `match g { Circle(x) => ... }` 变体绑定臂解引用 `[rax+off]` 取数据。
- 因此 enum 变量的**数字/区间臂**（`match g { 0 => ... }`）按地址比较，
  不会命中 —— 这是与 enum 构造表达式（R_ETY 直接是 variant struct，
  v1.1152 对构造做 `[rax]` 解 tag）的已知差异。变体绑定臂是主要用法，
  数字臂请对构造表达式使用（`match Sh.Circle(5) { 0 => ... }`）。

## 验证

`tests/334_enum_global.mo`：全局 `g = Sh.Square(7)`、局部
`s = Sh.Circle(5)`、返回 `Sh.Circle(9)`，三个值分别 match 变体臂取数据
求和 → `5 + 7 + 9 = 21`，RC=21。