# v1.1156: const fn 分支支持（if / else + 比较运算符）

## 概述

v1.1155 的 const fn 体只支持纯算术 `return`——`if` 块被体扫描**静默跳过**，
只折叠最后一个 return，导致 `max(7,3)` 这类代码**算错数不报错**。
v1.1156 将 cfn_eval 升级为递归语句解释器，支持任意嵌套的 if/else 与
全部六个比较运算符。

## 新能力

const fn 体内可写：

- `if cond { return expr; }`（无 else）
- `if cond { ... } else { ... }`
- 嵌套 if / else（任意深度，如 grade 分档）
- 比较运算符：`== != < <= > >=`（返回 0/1，优先级最低）
- 条件中可含完整算术表达式：`if a * 2 + 1 > b / 2 { ... }`

## 实现

- `cfn_run(limit)`（part5）：递归块执行器。遇到 `}` 消费并返回本层；
  return 求值后写全局 `CFNRV` 并置 `CFDONE=1`（后续语句跳过）。
  条件假时按括号深度整块跳过。guard 计数 >50000 硬退出防死循环。
- `cfn_eval(fid, abase)`：保存位置/上下文 → `cfn_run(cbe)` → 恢复 → 返回 CFNRV。
- `cfn_expr`：比较层**放在加减 while 之后**（`a*2+1 > b` 的左值要先吃完 `+1`，
  否则比较被静默丢弃）。rhs 用 `cfn_expr(0)` 递归（链式比较 a<b<c 从左结合）。
- 全局 `CFNRV`/`CFDONE`（part1）：解释器返回值与完成标志。

## 已知限制

- 不支持循环（while/loop）、赋值语句、非 return 的提前退出。
- 条件与表达式必须是编译期可求值（参数、字面量、算术、比较）。
- 比较链 `a < b < c` 按左结合解释（(a<b)<c），与 C 语义一致。

## 测试

- tests/336_constfn_branch.mo：max/min/clamp/sign/grade（嵌套 else）
  + 复合算术条件，expect 142。
- 门禁 487/0（v1.1155 的 335=98 回归通过）。

## 调试教训（写给后续开发者）

1. **块扫描循环必须有 POS 边界**：`while d > 0` 只靠括号计数，
   done 后括号不再计数就会扫到文件尾无限空转（300 万轮探针实锤）。
2. **expect 失败不终止编译**：syntax_error 返回 -1，token 不动，
   外层 while 若无步进保护就是死循环。
3. **自举编译器的 UB 掩盖**：调试中遇到「加 syscall 探针就正常、
   删掉就死循环」的现象——探针改变栈/寄存器布局掩盖了越界写。
   最终以 `while cond && guard >= 0`（guard 参与代码生成）绕开并保留。
4. 残留 out.elf 僵尸进程会让 `rm -f out.elf` 后跑旧 elf / cp 覆盖失败
   （ETXTBSY），测试前必须 `pkill -9 -f out.elf`。
