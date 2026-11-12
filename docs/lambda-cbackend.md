# mo2x lambda 表达式（v1.1166）

## 概述
mo2x（emit 型直产 C 文本后端）从 v1.1166 起支持 lambda 表达式（无捕获闭包），
仅限 C 系后端（c / cfs / kern / uefi）；js / py 目标报错
"lambda 仅在 C 系后端支持"。

## 语法（与 moc 侧 v1.1165 一致）
```
let f: ptr = fn(x: i64) -> i64 { return x * 2; };
apply(fn(n: i64) -> i64 { return n + 1; }, 9);
```

## 架构
1. **prescan_lambdas()**（main 里 emit_header 之前）：对已加载文件逐个
   load_file + tokenize，扫 `fn` 后紧跟 `(` 的 lambda（函数定义是 `fn 名字(...)`，
   lambda 是 `fn(...)`，以"fn 后第一个 token 是否 '(' "区分），配平 `{}` 收集
   token 文本（token 间补空格防粘连）到 LAMSRC[NLAM*8192]。
2. **emit_lambda_decls()**（emit_header 后立即）：逐条 re-tokenize，
   emit_sig() 发真原型前向声明 `static long long mo_lambda_N(long long x);`。
   位置必须在所有使用点之前 —— 这是单遍流式输出的关键约束，
   所以收集必须提前到 header 之前完成。
3. **collect_lambda()**（emit_unary 的 `fn` 分支，kind=2 函数体轮）：
   不再收集（prescan 已做），只消费序号 LAMCN++、配平跳过 lambda 体 token、
   发表达式值 `((unsigned char*)mo_lambda_N)`。
4. **resolve_lambdas()**（footer 前）：逐条 re-tokenize 发
   `static long long mo_lambda_N(...)` 定义。

## 附带修复：ptr 变量 fnptr 调用（mo2x 历史缺口）
t179（f(x) 形参 ptr 调用）在 mo2x C 后端一直静默产出坏代码
（`((long long(*)(void))f)()`，实参丢失）。v1.1166 新增 PTRV 表
（emit_scalar_or_arr 的 ptr 局部 + emit_sig 的 ptr 形参注册），
调用点 `f(args)` 按**顶层实参个数**（配平扫描，逗号数+1）发对应
函数指针原型 cast：`((long long(*)(long long))f)(x)`。
修复后 t179 = 42 ✓。

## 坑
- '(' 由 emit_primary 调用分支统一消费 —— ptr 分支里不能再 TI+1（否则预扫
  从 ')' 开始，na_t 恒 0）。
- 声明不能用 K&R 无原型 `mo_lambda_N();`：zig cc 默认按 C23 语义视作
  零参数原型，与定义冲突。
- lambda 文本前缀 `fn mo_lambda_N`，编号占位 'N' 在 base+13，需按十进制覆盖。
- prescan 与正文必须同序：同一次 tokenize 的 token 流顺序天然一致。
