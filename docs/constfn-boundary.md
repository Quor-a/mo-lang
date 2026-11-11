# const fn 递归解释器边界修复（v1.1157）

## 背景

v1.1156 引入了 const fn 分支支持（if/else + 比较运算符），采用递归解释器 `cfn_run(limit)`。
但在自举后暴露出一个严重 bug：**嵌套 if/else 的块边界计算错误**，
导致 `max(7,3)` 返回 3 而非 7、`min(9,4)` 返回 0 而非 4。

## 根因

Mo 编译器的 token 流中，`gv(K_POS)` 的语义是**当前 token 的结束偏移**（`lex_ident` 里 `sv(K_POS, p + i)`），
而 `gv(K_TOKPOS)` 才是**当前 token 的起点**。

v1.1156 的 `cfn_run` 在扫描 if 块尾时：
1. 用 `gv(K_POS)` 记录块尾 `}` 的偏移 —— 实际记录的是 `}` 的**结束位置**，且 set_pos 时从错误位置重读
2. 递归调用 `cfn_run(limit)` 时，limit 是块尾 `}` 的结束偏移，导致递归进入时 `gv(K_POS) < limit` 立即为假，**if 块内语句一个都没执行**
3. 于是 if 真分支被跳过，函数落到最后的 `return b`，返回错误结果

## 修复

v1.1157 重写 `cfn_run` 的 if/else 处理：

- **块首**：`expect("{")` 后当前 token 的起点用 `gv(K_TOKPOS)` 记录（`bstart`/`ebstart`）
- **块尾**：扫描到本层块尾 `}` 时，用 `gv(K_TOKPOS)` 记录其起点（`eend`/`eend2`）
- **递归**：真分支 `set_pos(bstart)` 回到块首，`cfn_run(eend)` 以块尾 `}` 起点为 limit
- **返回**：递归停在块尾 `}` 上（`gv(K_POS) == limit` 时循环退出），外层 `next_token()` 消费 `}`

这样 if 块内语句（包括嵌套 if/else）被正确执行，且不会越过块边界。

## 验证

- `max(7,3)=7`、`min(9,4)=4`、`grade(70)=3`、`grade(10)=1`、`sign(0)=0` 全部正确
- tests/336_constfn_branch.mo = **142**（回归通过）
- tests/335_constfn_multi.mo = **98**（多参数回归通过）
- **自举成功**：`/tmp/moc1157 src/compiler.mo` 生成 md5 完全一致的编译器

## 关键教训

`gv(K_POS)` 是 token **结束**偏移，`gv(K_TOKPOS)` 才是 token **起点**。
凡是用 `set_pos(p)` 重读 token 流的，p 必须是 **token 起点**（K_TOKPOS 语义），
否则会从 token 中间/间隙开始 lex，导致静默跳过语句。
