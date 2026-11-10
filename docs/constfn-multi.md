# const fn 多参数（v1.1155）

## 语法

```
const fn NAME(p1: i64, p2: i64, ...) -> i64 {
    return <算术表达式>;
}
```

- 最多 **8 个参数**（超过报错）。
- 参数名在函数体内可用，作为对应实参值。
- 函数体支持完整算术：`+ - * / %`、括号、一元负号。
- const fn 体可以**嵌套调用其它 const fn**（编译期折叠）。
- 调用点实参必须是**常量表达式**（字面量、const、或其它 const fn 调用）。

## 示例

```
const fn hypot(a: i64, b: i64) -> i64 {
    return a * a + b * b;
}
const fn scale(a: i64, b: i64, k: i64) -> i64 {
    return hypot(a, b) * k;   # 嵌套调用
}
fn main() -> i64 {
    return hypot(3, 4) + scale(3, 4, 2);   # 25 + 50 = 75
}
```

## 实现要点

- 参数名序列紧凑写入 `O_CFA` 名区（`[nargs:8][name:16]...`），
  `O_CFNP` 表记录 `fid → 名区偏移+1`。
- 实参求值到独立帧（`O_CFA + 62000 + CFARGD`，每帧 64B 可容 8 个实参），
  `CFARGD` 分层防止嵌套调用覆盖父帧。
- `cfn_eval(fid, abase)` 保存/恢复 `CFCUR`、`CFABASE`，用帧基址取实参。
- `cfn_atom` 按当前函数（`CFCUR`）的参数表逐个比对名字，命中返回
  `CFABASE + i*8` 的实参值。
- `cfn_expr` 新增 `+ -` 处理（v1.1155；此前 const fn 仅支持 `* / %`）。

## 测试

- `tests/335_constfn_multi.mo`（多参数、嵌套、加减乘除、const 声明内调用，
  输出 98/RC=98）
- 回归：`tests/295_constfn.mo`（单参数嵌套折叠）