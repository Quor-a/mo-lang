# enum impl 方法 (v1.1150)

`impl EnumName { ... }` 为 enum 定义方法，方法第一个参数是 `self`（无类型注解，语义等价 `self: EnumName` = tag+data 的 i64 值）。

```mo
enum Op { Add(i64); Sub(i64); None; }
impl Op {
    fn apply(self, x: i64) -> i64 {
        match self {
            Add(k) => { return k + x; }
            Sub(k) => { return k - x; }
            _ => { return 0 - 1; }
        }
    }
}
fn main() -> i64 {
    let a = Op.Add(10);
    return a.apply(5);   // 15 —— 方法调用语法
}
```

要点：
- 方法体内部 `self.other_method(...)` 链式调用可用。
- 方法名生成 `EnumName_method`，与普通函数同命名空间（不要手动定义同名函数）。
- `impl Iface for Type { ... }` interface 实现语法不受影响。
- 已知限制：无数据变体（`Op.None`）构造为 Enum 常量（i64 tag），对其调用方法报 not a class value；用带数据的变体或 match 通配臂处理。
