# v1.1153: enum 形参值语义修复

## 背景
`enum Sh { Circle(i64); Square(i64); }` 这类**带数据变体**的 enum，
跨函数传参后在函数内**值用**（算术 `s + 1`、`print_i64(s)`、把数据
取出来算）全部得到栈地址——而不是传入的值。

## 根因
`enum_type_exists()` 原本只扫描 **O_ENAME/O_ECNT**（`enum_add_const`
填充的简单 enum 常量表）。带数据变体走的是 v1.1142 的
**EV_E/EVCNT** 表，**不在 O_ENAME 里**：

- `fn area(s: Sh)` 的类型解析：`st_lookup("Sh")` 失败 →
  `enum_type_exists("Sh")` 返回 0（简单表查不到带数据 enum）→
  走 v1.1110 **前向 struct 注册** → `pt = ty_struct` + O_SP=1
  （引用语义，槽内存对象地址）。
- 被调端 v1.1057 设计「enum 形参等价 i64」（值语义）——但登记
  的 ty 却是 struct，`load_sym` 按引用发 `lea`，函数内拿到地址。

两端语义错位，于是跨函数双数据变体全部按地址用。单数据变体
（328）恰好 match 也按地址解，所以一直没暴露。

## 修复
`enum_type_exists()` **同时查两张表**：

```mo
while i < load64(heap + O_ECNT) {   # 简单 enum（enum_add_const）
    if streq(heap + O_NAMES + load64(heap + O_ENAME + i*8), ...) == 1 { return 1; }
    ...
}
while j < load64(heap + EVCNT) {    # 带数据变体（v1.1142 EV_E）
    if streq(heap + O_NAMES + load64(heap + EV_E + j*8), ...) == 1 { return 1; }
    ...
}
```

`"Sh"` 现在被识别为 enum → 形参 `pt = ty_int()`（v1.1057 语义），
值按 i64 传递；简单 enum 的 `let c: Color` / `var g: Color` 类型注解
也保持可用（O_ENAME 表仍查）。

## 验证
- `tests/333_enum_param_value.mo`：双数据变体跨函数，match 取数据
  再算术 —— 输出 `69`（5+1、7+2），RC=6。
- 回归：235=4、236=22、328=10、331=15、332=25 全对。
