# Lambda 表达式（v1.1165）

## 概述

v1.1165 为墨语言补上主流语言史上最悠久的缺口之一：**lambda / 匿名函数**。
谱系：ML(1978) 首创 → Scheme/Ruby 广泛化 → 现代 Swift/Kotlin/Rust/Java 标配。
Mo 此前只有命名函数 + `&fn` 取址；现在函数可以是**表达式**。

## 语法

```
let f: ptr = fn(x: i64) -> i64 { return x * 2; };   # 赋给变量
apply(fn(n: i64) -> i64 { return n + 1; }, 9);      # 内联实参
```

- 与命名函数同一套参数/返回类型语法（含多参、ptr/byte/f64）。
- 返回类型可省略（与 fn 一致）。
- 表达式值 = 生成的隐藏函数 `__lambda_N` 的地址（ptr），可用既有
  fnptr 调用约定 `f(args)` 调用。

## 实现（零 AST 架构）

1. `parse_unary` 遇 `fn`（表达式位置）→ `parse_lambda()`：
   从源码**逐字节复制** lambda 文本（参数表 + 体）到 `O_LAMTXT`
   队列（每条 16KB，上限 64 条），命名 `__lambda_N`；在表达式位置
   发射 `movabs rax, <imm64 前向占位>`（与 `&fn` 前向引用同构）。
2. `parse_program` 主循环结束后 `resolve_lambdas()` 逐条：
   `sym_add` 登记名字（名字截断到 `(` 前 —— 文本中无 0 结尾）→
   切 `K_SRCBASE` 到文本 → `parse_func()` 正常编译（签名、局部变量、
   return 全走既有路径）→ 回填占位地址（ELF 模式写 8 字节立即数；
   `-c` 模式登记 `R_X86_64_64` 重定位）。

## 已知局限

- 函数体的 `{}` 按**朴素配平**复制：字符串/字符字面量中的 `{` 或
  `}` 会干扰配平（lambda 体通常不含此类内容）。
- lambda 无捕获（捕获环境需显式传参）；闭包捕获留待后续版本。
- mo2x 的各后端（c/js/py/...）尚未支持 lambda（v1.1166 范围）。
- 🔴 用户函数不可命名为内建 `call0/call1/call2/call3`（内建拦截
  优先于用户符号 —— 既有约定，lambda 测试编写时踩过）。

## 测试

`tests/343_lambda.mo`（期望 64 = dbl(21) + inc(9) + x3(4) = 42+10+12），
moc ELF 与 `-c` obj 双链路验证。
