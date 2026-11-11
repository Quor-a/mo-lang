# const fn 循环、局部变量与赋值（v1.1158）

## 新增能力

const fn 体从「只有 return / if-else」扩展到可写**真正的循环代码**：

```mo
const fn sum_to(n: i64) -> i64 {
    let s: i64 = 0;
    let i: i64 = 1;
    while i <= n { s = s + i; i = i + 1; }
    return s;
}
const fn gcd(a: i64, b: i64) -> i64 {
    let x: i64 = a;
    let y: i64 = b;
    let t: i64 = 0;
    while y != 0 { t = x % y; x = y; y = t; }
    return x;
}
```

- `let name: i64 = expr;` —— 每层调用一帧局部变量（最多 8 个，名字 15 字节内）
- `name = expr;` 与复合赋值 `+= -= *= /= %=`
- `while cond { ... }` —— 任意嵌套，可与 `if` 混用，循环体内可调其它 const fn
- 局部变量遮蔽同名的 const fn 参数

## 三个必修的 bug（本轮全部实测定位）

### 1. 嵌套调用不恢复 CFDONE → 循环体只执行一次

`cfn_eval` 进入时把 `CFDONE` 清零、命中 `return` 时置 1，但**返回时没有恢复**。
循环体内调用任何 const fn（其体里必然有 `return`）之后，外层 `cfn_run` 的
`while ... && CFDONE == 0` 立刻看到 1 就收工：
`while i <= n { s = s + sq(i); i = i + 1; }` 只跑一轮，`i` 永不递增。

修法：`cfn_eval` 保存 `CFNRV`/`CFDONE` 进入，退出时先取结果再恢复。

### 2. 嵌套调用的实参帧与外层形参帧同一地址

```mo
let nabase: i64 = heap + O_CFA + 62000 + CFARGD;
let oldd: i64 = CFARGD;
CFARGD = CFARGD + 64;
...
CFARGD = oldd;                      # ← 复位太早
let cfr: i64 = cfn_eval(nid9, nabase);
```
`nabase` 用的就是**当前帧**的地址，把 `CFARGD` 提前复位后，嵌套调用写实参
等于原地覆盖外层函数的形参 —— 循环条件 `i <= n` 里的 `n` 被 `sq(i)` 的实参
改掉，条件恒真，循环跑到 5000 轮保险丝才停（结果是个看不出规律的大数）。

修法：实参帧一律 `oldd + 64`，且 `CFARGD` 到 `cfn_eval` 返回后再复位。

### 3. 复合赋值被静默跳过

`i += 1;` 在语句分发里既不是 `let` 也不是 `name = ...`（`+=` 不是 `=`），
落到「未知 token 就 next_token 跳过」的兜底分支 —— **不报错、结果算错**。
按本项目一贯标准（静默错 > 报错），补上 `+= -= *= /= %=` 的支持。

## 实现要点

- 局部变量帧：`O_CFL = 8620000`（`O_MSYM` 之后的空档），每层 256B：
  `[count:8][名 16B + 值 8B] × 8`，`CFLGD` 记深度，`cfn_eval` 进出 ±1 并清零 count。
- `cfn_atom` 查名顺序：**局部 > 参数 > 其它 const fn 调用**。
- 循环回跳：记条件首 token 的 `gv(K_TOKPOS)`，每轮 `set_pos(cpos)` 重新求值条件；
  块尾同样用 `K_TOKPOS` 定位（v1.1157 的结论）。
- 保险丝：单层 const fn 循环 5000 轮上限（编译期折叠不应无限），`return` 立即停。

## 验证

- tests/337_constfn_loop.mo = **136**（9 个场景加权：累加/阶乘/迭代 fib/循环+if/
  循环内调 const fn/欧几里得/嵌套循环/循环内 return/复合赋值）
- tests/336 = 142、335 = 98 回归通过
- 门禁 **488/0**
- 自举：新编译器编译自身 md5 一致
