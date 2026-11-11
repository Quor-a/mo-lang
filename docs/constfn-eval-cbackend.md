# mo2x 支持 const fn 求值（v1.1163）

## 之前

mo2x（C 后端）对数组长度里的 `const fn` 调用直接报错：
`数组长度表达式引用了未定义的 const 名`。`const K: i64 = fact(4)+1;` 同样
被拒（`const 表达式不支持函数调用`）。只有 `moc`（自举编译器）能处理。

## 现在

mo2x 内置了一个 **const fn 解释器**，与 moc 的折叠语义对齐：

- 支持 `if / else` 任意嵌套、`return`、递归调用、多参数（≤8）、
  `+ - * / % << >> & | ^` 与全部比较运算
- 数组长度 `[fact(5)]`、`[gcd2(48,18)]`、`[fact(N)+1]`、`[f(4)][2]`（多维）全部求值
- 顶层 `const K: i64 = <含调用的表达式>;` 求值后 emit 成
  `enum { K = <数值> };`（C enum 不允许函数调用，故输出数值）；
  纯算式仍原样 emit，保留可读性
- c 目标的 `syscall()` 号透传（此前 c 目标没有号表，带 `io.mo` 的程序报
  "该目标架构暂无 syscall 号表"）

## 实现结构（tools/mo2x.mo）

- `collect_const_fn()`：pass1 遇到 `const fn` 时记录函数名、参数名、
  函数体 token 流（kind + 文本快照进 CFSRC/CFTK0/CFTS0）
- `cf_call_fn()`：帧式解释。每帧 512 token 槽（CFTKP/CFTSP），
  参数名/值存 CFNAME/CFVAL（每帧 512 槽），深度上限 128
- `cf_run_body()` / `cf_run_body_until()`：语句执行（return / if-else，
  10 万步防死循环安全网）
- `emit_dim_to_cache()`：长度表达式含 const fn 调用时整体求值输出数字，
  否则照旧原样 emit 给 C 折叠

### 踩过的坑

- **帧数组按 512 分段**：CFNAME/CFVAL 若小于 深度×512 会越界
  （表现为 "index out of bounds"）——初版 1024 长度在 3 层递归就撞线
- **if 分支处理完必须 `continue`**：否则落到"跳到 `;`"兜底，
  把外层 `return` 整个吞掉，函数返回 0 而不报错
- 参数查找不能靠"帧基址反查函数"—— 要在帧栈里记录函数索引（CFFI2）
- 求值发生在 pass1（var 轮），收集必须也在 pass1 且先于 var；
  token 快照与文本快照都取当轮（后续 pass 会重新 tokenize）

## 已知边界

- `const fn` 体内不支持 `while` / 局部变量 / `break` / `continue`
  （moc 支持；mo2x 遇到会在 10 万步后报"执行步数超限"或语法错）
- 函数体 token 上限 8192、单文件 `const fn` 个数上限 512
