# 墨语言（Mo）速查表 —— 给 AI 助手

墨语言是**自举的编译型语言**（编译器用自己写成），语法接近 C + Rust。
下面只列**最容易写错的地方**，不是完整教程。完整文档在 `docs/`。

## 编译与运行

```bash
./bin/moc prog.mo prog.elf      # 编译
./prog.elf                       # 运行
make test                        # 跑全部测试（tests/*.mo）
make boot                        # 自举校验
```

## 🔴 最容易写错的 13 件事

1. **符号必须先定义后使用**（无前向声明）。函数要调用它，就得写在前面。
2. **`let` 不能写在循环体内** —— 会累积栈帧。循环变量一律在循环外声明：
   ```mo
   let i: i64 = 0;
   while i < n { ...; i = i + 1; }
   ```
3. **全局数组声明必须带初值**：`var A: [64] i64 = 0;`
   （局部数组用 `var` 会报 undefined symbol —— 数组只能全局声明）
4. **没有 C 风格 `for` 循环**。`for` 关键字只用于 `impl Interface for Type`。
5. **没有 printf**。用 `print("x")` / `print_i64(v)`；格式化用 `sfmt`：
   ```mo
   sfmt(dst, f"共 {n} 篇");      # 只在 print() 和 sfmt() 里支持插值
   ```
6. **字符串是 `ptr`**，不是独立类型。`strlen` / `strcmp` / `strcat` 手写。
7. **函数返回类型不支持结构体**（>2 字段）。要返回多个值用 `ptr` 或全局变量。
8. **只有 `i64` / `f64` / `ptr` / `i32`(外部函数) / `bool` / `enum`**，
   `bool` 是 i64 的具名别名，不做隐式类型检查。
9. **🔴 `>>` 是算术右移（sar），不是逻辑右移**。要逻辑右移用
   `lib/hll.mo` 的 `hll_shr(x,n)`，或 `(x >> n) & ((1 << (64-n)) - 1)`。
   踩过的最狠一次：把 `lib/lsh.mo` 的 `lsh_mix`（用 `a ^ (a >> k)`）
   抄去做 HLL 的哈希 —— `a ^ sar(a,k)` 的 **bit63 = a63^a63 = 0**，
   **输出的 bit63 恒为 0**。LSH 里无所谓（64 位投票少一位看不出来），
   HLL 里致命（桶号取最高 p 位，bit63 是桶号最高位 ⇒ 只用一半桶）。
   症状是 V 恰好停在 m/2 且不再下降，估计值始终是个像样的数，不报错。
   → 凡"从别的库抄原语"，都要检查它在**新场景**下的前提还成不成立。
10. **全局变量不支持 f64**：`var A: f64 = 0.0;` → `error: expected a type`。
    f64 只能用局部变量；要跨函数传就存 `fbits(x)`（位模式）到 i64 全局。
11. **没有 f64→i64 转换**（`i64(x)` 不存在，只有 `f64(x)`）。
12. **freestanding 后端（`cfs-*`）没有 `load8` / `store8`**（原生后端才有）。
    用到就是 C 编译期 `call to undeclared function 'load8'`。
    要验证读回的字节，把它 **write 回 stdout 让脚本 grep**，别在程序里自证。
13. **freestanding 后端里 `syscall()` 的实参个数要按目标架构算**：
    `open`/`mkdir`/`unlink`/`stat`/`access` 在 aarch64 会适配成 `*at` 版本，
    编译器**自动插入**首参 `AT_FDCWD(-100)`。所以源码里要**少写一个**占位
    实参，否则适配后超出 `mo_syscall` 的 7 个形参 → 编译失败。
    （`write`/`read`/`close` 不适配，照常写满 7 个。）
    测试里不要试图把 f64 转整数再断言 —— 直接用 f64 比较得出 0/1
    传给 `assert_true`，例如
    `let ok = 0; if v >= lo { if v <= hi { ok = 1; } } assert_true("...", ok);`
14. **🔴 循环里遍历数据时，"声明为 0 却从不加载"是最阴的一类漏写**。
    `let op: i64 = 0;` 后在 `while` 里加载了 a/b/o/nr/nc，唯独忘了 op
    ⇒ op 恒 0 ⇒ 下面十几条 `if op == OP_XXX` 分支**一条都不命中**，
    梯度全 0、不报错不崩溃。`lib/autodiff.mo` 里 8 个遍历 tape 的函数
    有 5 个写对了、3 个漏了（ad_backward / ad_forward / ad_audit），
    漏的那三个让 17 个测试全红。
    → 防御写法：能"声明即加载"就别先置 0 ——
      `let op: i64 = load64(&AD_TOP + t * 8);`（写对的 5 个都是这种）。
    → 变异守护：`make adopmut`（把三处改回 `op = 0`，必须变红）。

## 常用

```mo
import "io.mo";                  # 库在 lib/，import 用相对名
fn add(a: i64, b: i64) -> i64 { return a + b; }
var G: i64 = 0;                  # 全局
let x: i64 = 5;                  # 局部
if a > b { ... } else { ... }
while i < n { ... }
x /= 7;  x %= 100;  x += 1;      # 复合赋值（1.68 起 seed 也支持）
let p: ptr = &G;                 # 取地址
enum Color { RED = 1; GREEN = 2; }
class Rect { w: i64; h: i64; }
fn area(self: ptr) -> i64 { ... }        # 方法：Rect_area
let r: Rect; r.area();                   # 方法调用语法糖
```

## 写测试

`tests/NN_*.mo`，`main` 返回 0 = 通过。用 `assert.mo`：
```mo
import "assert.mo";
eq(实际, 期望);   # 失败时 F += 1
```
`make test` 会编译并运行全部用例。

🔴 **构建失败时旧产物会残留，然后被"执行"** —— 判据全绿，其实跑的是上一个
版本。写 shell 验证脚本时：先 `rm -f $OUT`，再把「构建」的退出码单独判，
失败就 `fail+=1` **并跳过执行**（不要只 `if [ -x $OUT ]`）。
v1.153 就是这个坑让一个真变异（M1）打印成"未被捕获"。

## 神经网络 / 自动微分

只写前向，梯度由语言算（`lib/autodiff.mo`）：
```mo
let w: i64 = ad_weight(32768);   # 可训练
let x: i64 = ad_input(65536);    # 输入
let y: i64 = ad_sigmoid(ad_mul(w, x));
ad_backward(y);                  # 自动反向
ad_step(6553);                   # lr ≈ 0.1
ad_audit();                      # 梯度流审计，抓静默的断裂
```
值都是 **Q16.16 定点**：1.0 = 65536，0.5 = 32768。

⚠️ 定点饱和区比浮点窄：初始化取 ±0.5 量级，别用大值，否则隐藏单元会
从头到尾收不到梯度（`ad_audit()` 能报出来）。

## 不要猜

不确定的语法先查 `tests/` 里有没有用例 —— 那里是唯一的可信来源。

## 最容易写错的：cfs 后端（mo2x）的 32 位移位

生成到 C 之后，以下两种写法在**移位量 >= 32 时是未定义行为**，LLVM 直接折成 0。
不报错、不崩溃，只表现为数值恒错：

```mo
(1 << r)                    # 字面量 1 是 int（32 位）
load8(p + j) << (j * 8)     # 字节被提升成 int
```

实测：`rotl64(1, 13) = 8192` 正常，`rotl64(1, 32) = 0`（应为 4294967296）。
**小移位量下完全正常，只有 << 32 / << 56 才发作**，所以抽查小值是永远碰不到的。

正确写法：让 i64 变量承载。

```mo
let one: i64 = 1;
return (x << r) | ((x >> (64 - r)) & ((one << r) - 1));

bb = load8(p + j);          # 先落进 i64
m = m + (bb << (j * 8));
```

另外：**`常量 << 常量` 的常量折叠只按 32 位算**（`1936682341 << 32` 折成 0，
而变量 `v << 32` 正确）。构造 64 位常数请直接写完整十进制字面量，不要拼。

这类缺陷只有靠**独立参照**才能逼出来 —— 例如标准算法的官方测试向量。
