# enum 判别式的数字/区间臂 tag 匹配（v1.1152）

enum 值的 match 现在**同时**支持变体名臂与数字/区间臂 —— 数字臂按变体 tag 比较：

```mo
enum C { A(i64); B(i64); }
fn main() -> i64 {
    let c = C.B(2);
    let x: i64 = match c {
        0 => 5,       // A 的 tag 是 0
        1..3 => 25,   // 区间臂：B 的 tag 1 ∈ [1,3]
        _ => 0,
    };
    return x;         // 25
}
```

## 背景（真 bug 修复）

enum 值在运行时是 variant struct（tag 在 offset 0），match 的判别式
寄存器里是该对象的**地址**。v1.1152 之前数字/区间臂直接拿地址与常量
比较 —— 永不命中，静默走 `_` 或掉出 match。修复：判别式类型是
variant struct（类型名含 `$`）时，比较链前先解引用一次
（`mov rax,[rax]`）取 tag。

## 穷尽性

区间臂 `lo..hi` 覆盖 `[lo,hi]` 闭区间内**全部**变体 tag：

```mo
let c = C.A(1);
match c {
    0..1 => { }   // 覆盖 A(0) 与 B(1) —— 穷尽，无需 _
}
```

`0..0` 只覆盖 A；若 B 未被任何臂覆盖则报"未穷尽"。

## 已知限制（既有，未变）

- **跨函数传递双数据变体 enum 实参**后 match 可能不命中
  （单数据变体正常、局部判别式正常）。独立问题，另行修复。
- 无数据变体（`Op.None`）构造为 enum 常量（i64 tag），对其调用
  方法报 not a class value。
- 函数返回 enum 变体对象不支持。
