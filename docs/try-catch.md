# try / catch（v1.1172）

## 语法

```mo
try {
    r = a[i];          # 越界 panic 被捕获
} catch(e) {
    # e = 错误码（越界 = 1）。错误码可用可不用：写 `catch` 也合法。
}
```

## 实现原理

- 编译期维护 catch 标签栈 `TryLS[64]`（K_TRYD = 嵌套深度）。
  `panic_label()` 在 K_TRYD > 0 时返回 `TryLS[K_TRYD-1]`，
  所以 try 块内所有越界检查点 `ja` 直接跳到最近的 catch（嵌套取最内层）。
- 进入 try 时发射 `movabs rax, slot; mov [rax], rsp` 把当前栈指针
  存进数据段槽（每个 try 独占 8 字节，编译期从 K_DLEN 分配）。
- 异常路径上可能有未清的 push，所以 catch 入口先
  `movabs rax, slot; mov rsp, [rax]` 恢复栈，再把错误码 1
  写进 catch 变量 e（`movabs rax, 1; mov [rbp+off], rax`）。
- try 块正常结束 `jmp` 到 catch 之后的汇合点，不经过恢复序列。
- catch(e) 的 e 以当前块深度 d 注册进符号表，catch 块结束时
  由 parse_block 的 sym_pop_scope(d) 清除 —— 两个并列的 try 可以
  都用 catch(e)。

## 限制

- ⚠️ 只捕获**同函数内**的越界 panic。被调函数里越界时不经过
  调用者的 catch：栈帧未清理，直接跳会撞上错误栈 —— 仍走全局
  panic 例程（打印 `mo: index out of bounds` 并 exit(1)）。
- 捕获后程序状态（部分写入的变量、库内部结构）不做回滚，
  catch 是恢复点不是事务边界。
- 嵌套上限 64 层；try 只允许出现在函数体内。

## 历史

- v1.1172: 初版（同函数越界恢复）。tests/352 覆盖：正常路径不进
  catch、嵌套内层捕获、外层捕获、循环体内 try。

## panic("msg")（v1.1175）

```mo
try {
    if bad { panic("bad state\n"); }
} catch(e) {
    # e = 2（panic）；越界 = 1
}
```

- 实参须为字符串字面量（编译期已知长度）；写 stderr 后：
  在 try 内 → 跳最近 catch，e = 2；无 try → exit(1)。
- 错误码经数据段 errslot 传递（每 try 层一个槽，catch 进入时读取
  并清零：0 视为越界=1，2=panic）。
