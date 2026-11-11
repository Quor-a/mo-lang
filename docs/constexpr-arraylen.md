# 数组长度接受常量表达式（v1.1162）

## 之前的限制

全局数组声明 `var A: [N] i64 = 0;` 的长度位置只认两种东西：

- 十进制/十六进制整数**字面量**（`[16]`、`[0x10]`）
- 已定义的 `const` 名（`[N]`，N 是 const）

除此之外全是 `error: syntax error`，包括再普通不过的算式：

```
var A: [2+3] i64 = 0;      # error: syntax error
var B: [10*2] i64 = 0;     # error: syntax error
var C: [1<<4] i64 = 0;     # error: syntax error
var D: [gcd(48,18)] i64 = 0;  # error: syntax error（const fn 调用）
```

于是「缓冲区大小由一个常量推导出来」这种最基本的写法只能靠人手算好再写死 ——
改一个因子就要回头改所有数组声明，且手算的个数一旦和 `SZ` 常量脱节，
越界写就是静默踩内存。

## 改法

数组长度的解析点一共 5 处（`parse_let` 的第一维/内维、`parse_global` 的第一维/内维、
`try_parse_type` 的数组类型），全部改成直接调用编译器已有的 `const_expr()`。

`const_expr()` 是编译期常量求值器（`const` 声明、enum 值、`sizeof`/`alignof`、
`const fn` 折叠共用同一套），因此一次性就支持了：算术 `+ - * / %`、移位 `<< >>`、
位运算 `& | ^`、比较、逻辑运算符、括号、`const` 名、enum 值、
`sizeof(T)`/`alignof(T)`、以及 **`const fn` 调用**（可递归）。

## 🔴 踩到的坑：数字快速路径

第一版保留了原来的「第一个 token 是数字就直接取 `K_TIVAL`」快速路径：

```mo
if gv(K_TKIND) == 2 { n = gv(K_TIVAL); next_token(); }
else { n = const_expr(); }
```

于是 `[2+3]` 走快速路径：吃掉 `2` 之后 token 停在 `+` 上，紧接着 `expect("]")`
报语法错，**位置指向 `+`**（列 11），而后又连锁报出 `expected a type`。
`[(2+3)]` 却是好的 —— 因为括号让它绕开了快速路径，走 `const_atom` 的 `(` 分支。
这个「加括号就正常、不加就报错」的分裂现象是最先暴露问题的线索。

修法：删掉快速路径，一律走 `const_expr()`（`const_atom` 本来就能处理裸数字，
快速路径是纯冗余）。

## 边界行为

长度求值为 `<= 0` 时仍是硬错误，且报在**声明位置**而不是表达式结尾：

```
var A: [2-3] i64 = 0;   # error: array length must be a positive constant
var A: [0] i64 = 0;     # error: array length must be a positive constant
```

## 测试

`tests/340_constexpr_arraylen.mo`（expect **145**），9 个数组覆盖：

| 形式 | 长度 |
|---|---|
| `[2+3]` | 5 |
| `[10*2]` | 20 |
| `[1<<4]` | 16 |
| `[gcd2(48,18)]`（const fn） | 6 |
| `[fact(5)]`（递归 const fn） | 120 |
| `[N]`（const 名） | 4 |
| `[fact(N)+1]`（混合） | 25 |
| `[N*2][3]`（内维也走表达式） | 8 × 3 |
| `[(2+3)*2]`（嵌套括号） | 10 |

期望值由 Python 独立模型算出：取值加权和 309 + 总槽数 214 mod 256 × 10 = 2449，
`2449 % 256 = 145`。

回归：门禁 **491 / 0**，自举 md5 一致（`f36d4636…`）。
