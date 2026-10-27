# 对标 Shell + WebAssembly 运行环境

版本 1.19.0（2026-10-09）

两件事：

1. **`lib/sh.mo`** —— shell 的底层能力，并用它写出了 **`examples/mosh.mo`**（一个真能用的 shell）
2. **`tools/wasm.sh` / `tools/wasmtest.sh`** —— WebAssembly 目标，**能真正执行并比对输出**

第 2 件尤其重要：这是本项目**第一次拿到运行时验证**。
此前的内核 / Windows / 安卓目标都只能验证产物结构正确，不能执行。

## 一、对标 Shell

一个 shell 的本质是四件事，`sh.mo` 逐个实现：

| 能力 | 函数 |
|---|---|
| 词法切分（引号、转义） | `sh_split(line, toks)` |
| 通配符 | `fnmatch(pat, s)` |
| 进程（fork/exec/wait） | `sh_fork` / `sh_execvp` / `sh_wait` / `sh_run` |
| 管道与重定向 | `sh_pipe` / `sh_pipe_exec` / `sh_redirect_out` / `sh_slurp` |
| 其它 | `sh_which` / `sh_chdir` / `sh_getcwd` / `sh_setenv` |

全部是系统调用，不依赖 libc。

### `examples/mosh.mo` —— 一个真 shell

```bash
./bin/moc examples/mosh.mo /tmp/mosh.elf && /tmp/mosh.elf
```

支持：外部命令、管道 `a | b`、重定向 `>` `>>`、内建
`help exit cd pwd echo env which status`、引号与转义、`*`/`?` 通配符。

实测：

```
mo$ echo a b c | wc -w
3
mo$ echo hi > /tmp/t.txt
mo$ ls /tmp | head -3
```

### 踩到的坑：`pipe` 返回的是两个 int，不是两个 long

这是本轮最值钱的发现。

`pipe(2)` 写入**两个 4 字节 int**，而我按 `i64` 读，于是两个 fd 挤进同一个
8 字节槽：

```
fds[0] = 0x0000000400000003 = 17179869187    ← 两个 fd 粘在一起
fds[1] = 0
```

症状是 `dup2` 收到无效 fd，命令报 **"Bad file descriptor"**——
看起来像管道逻辑写错了，实际是读法错了。

修法：按 32 位拆开。

```mo
let v: i64 = load64(&raw);
store64(out,     v & 4294967295);          # 读端
store64(out + 8, (v / 4294967296) & 4294967295);   # 写端
```

> 系统调用的结构体布局必须逐个字段核对，不能按"都是 64 位"想当然。

### 另一个坑：忘了 `heap_init()`

`str_dup` 走 mem.mo 的 bump 分配器，而 `hp` 初值是 0——
不初始化就 `alloc` 会返回地址 0，一写就段错误（rc=139）。

这类"忘了初始化"的错误在墨语言里**没有任何提示**，只能靠记住。
凡是用了 `str_dup` / `dir_list` 的程序，`main` 开头都要 `heap_init()`。

### 没做

- **作业控制**（fg/bg/Ctrl-Z）：需要终端会话与信号组
- **命令替换** `$(...)`、函数、别名：属于 shell 语言层，不在本库范围
- **环境变量**：墨语言不暴露 `environ`，`sh_setenv` 是**自建表**，
  只做"追加/去重"，不做 `KEY=` 前缀匹配查找

## 二、WebAssembly：第一次真正跑起来

```bash
bash tools/wasm.sh examples/wasmdemo.mo /tmp/demo.wasm
```

```
Mo -> WebAssembly (WASI)
0 1 1 2 3 5 8 13 21 34 55 89 144 233 377 610 987 1597 2584 4181
sum=10945
-42
```

`tools/wasmtest.sh` 做**跨环境一致性验证**：同一份源码，
原生 x86-64 与 WASM 的 stdout 必须**逐字节一致**。

### 为此修掉的问题

**1. `syscall` 在 WASI / Windows 上不存在**

前导无条件 `#include <sys/syscall.h>` 会让这两个目标直接编译失败。
改成按平台条件编译：

```c
#if defined(__linux__) && !defined(__wasi__)
  ...真 syscall...
#else
  ...返回 -1，明确表示不可用...
#endif
```

选"返回 -1"而不是"静默成功"，是因为用了 syscall 的程序应当看得出来。

**2. `print` 家族由**后端**提供，不是由源码提供**

原生后端用 `io.mo`（syscall write），C/WASM 后端用前导里的 `printf` 版。
mo2x 会跳过源码里 `print` / `print_i64` / `print_nl` 的实现，
改用后端自己的版本——否则 WASM 会因为照搬 syscall 版而链接失败。

**3. mo2x 的 token 缓冲会溢出**

import 进来的库是**全部拼在一起**词法化的，`str.mo` + `mem.mo` 就超过了
原来的 6000 上限，后面的 token 被静默丢弃。

症状离根因很远：报错是 `lib/mem.mo:37: expected operator at '<eof>'`——
看起来像"mem.mo 的语法不支持"，实际是缓冲满了。已扩到 20000。

**注意：这个问题没有完全解决。** 更大的库组合（如 `io.mo` 的完整依赖链）
仍会在 mo2x 里失败，已列为已知限制。

### 一个诚实的说明：退出码不比对

`wasmtest.sh` **只比对 stdout，不比对退出码**。

原因：实测 node 的 WASI(preview1) **不传播退出码**——用一个
`int main(){return 3;}` 的极小 wasm 验证过，node 直接返回 0。
所以比对退出码会永远失败，而那不是墨语言的问题。

## zig 依赖

系统级目标（内核 / UEFI / Windows / 安卓 / 交叉 / WASM）都靠 `zig`
提供交叉编译与各平台 libc。它由 **`tools/zigcc.sh`** 统一检测：
缺失时自动 `pip install ziglang`，装不上就给出明确指引。

为什么需要这一层：直接在脚本里写 `python3 -m ziglang cc` 时，
zig 缺失的报错是 `No module named ziglang`——完全看不出该做什么。

## 验证

```
测试 112 / 112（70_sh.mo 新增 34 条断言）
自举三级一致
wasmtest: 原生与 WASM stdout 逐字节一致
multibackend: 10 × 5 全对齐
targets: 27 项系统级自检
```

## 仍然没做到的

- **mo2x 解析大库依赖链仍会失败**（token 缓冲，见上）
- 内核 / 安卓 / `.ko` **仍然没有运行时验证**
- mosh 没有作业控制与命令替换
- WASM 目标不走原生后端，而是经 C 后端——不是独立的 WASM 后端
