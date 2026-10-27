# 包管理在安卓上运行

`examples/pkgarm.mo` + `tools/pkgarmtest.sh`（21 项断言，ARM64 与 x86-64 两端对照）

```
make pkgarmtest
```

## 一、诊断：照搬 `lib/mopkg.mo` 上安卓，第一步就走不通

现有包管理器走 `sh_capture`，即 **fork + pipe + dup2 + execve + wait4** 执行
外部命令（`lib/sh.mo`），并且依赖 **git** 做 clone / rev-parse（`lib/mopkg.mo`）：

| sh.mo 里的调用 | x86-64 号 | 在 cfs-aarch64 上 |
|---|---|---|
| `sh_fork` | 57 | ARM64 **没有 fork**，只有 clone(220)，参数形态完全不同 |
| `sh_pipe` | 22 | 翻译表查不到 → 构建失败 |
| `sh_dup2` | 33 | 同上 |
| `sh_chdir` | 80 | 同上 |
| `sh_getcwd` | 79 | 同上 |
| `sh_execvp` | 59 | 号有映射（59→221），但没有 fork 就没有意义 |

实测：任何一个 `import "sh.mo"` 的程序编到 `cfs-aarch64` 都会**直接失败退出**
（响亮报错，不是静默发错号 —— 这点是对的）。

**结论不是"补几个号就能上安卓"，而是模型本身要换**：freestanding 环境里
没有 fork/exec，包管理不能靠"起子进程执行命令"。

## 二、另一条路：包管理真正需要的只有五个 `*at` 调用

| 包管理动作 | 调用（x86 号 → aarch64） |
|---|---|
| 建包目录 | `mkdir` 83 → `mkdirat` 34 |
| 写文件 | `open` 2 → `openat` 56，再 `write` |
| 读文件 | `open` 2 → `openat` 56，再 `read` |
| 查询"装了没有" | `stat` 4 → `newfstatat` 79 |
| 卸载 / 清缓存 | `unlink` 87 → `unlinkat` 35 |

这五个在 v1.153 已做 `*at` 实参重排，**纯 syscall，不需要 fork / exec / git / libc**。
`examples/pkgarm.mo` 把它们串成一个完整的"安装—校验—卸载"闭环：

```
mkdir ret   = 0      # 建包目录
write bytes = 10     # 写清单
read bytes  = 10     # 关掉再打开，读回
read back   : MO-PKG-OK
stat ret    = 0      # 查询命中
unlink ret  = 0      # 删除
pkg ok      = 1
```

判据不靠程序自证：读回的内容**再写到 stdout**，由脚本 grep ——
程序自己写错了会一起错。

## 三、实测：两端给同一组数字

| 端 | 环境 | 结果 |
|---|---|---|
| A | ARM64，Unicorn 模拟 + 自制 syscall 表（内存文件系统） | 9 项全过 |
| B | x86-64，本机真跑静态 ELF，操作**真**文件系统 | 12 项全过 |

只跑 A 端，判据用的是模拟器自己实现的语义；只跑 B 端，验证不到 `*at` 号适配
（x86 不需要）。两端一致才说明"适配对了"，而不是"模拟器迁就了实现"。

B 端额外断言两件模拟器说不了的事：目录**真的**建出来了、unlink 后文件**真的**没了。

## 四、🔴 两个坑

### 一、freestanding 下零初始化大数组会引入 memset

```mo
let sbuf: [64] i64 = 0;    →  long long sbuf[64] = {0};
```

C 编译器把它优化成 `memset` 调用，而 freestanding 不链 libc：

```
ld.lld: error: undefined symbol: memset
```

**32 个 i64（armfs 的 `buf`）不会，64 个会。** 于是"多加一个数组"就让整个产物
链接失败，而症状完全不指向数组。修法：`sbuf` 不写 `= 0`（stat 会写它，不需要清零）。

### 二、模拟器的 `*at` 日志漏了 unlinkat / newfstatat

`tools/armrun.py` 此前只给 `openat` / `mkdirat` 记 dfd，于是 **unlinkat 与
newfstatat 的 dfd 从未被检查过** —— 正好是"重排漏了一个"最容易藏的地方。

已补齐，并给模拟器实现了 `newfstatat`（此前一律返回 `-ENOSYS`，示例只能报失败）。
现在断言 **5 次 `*at` 调用全部是 `AT_FDCWD(-100)`**，且 `N_ALL == N_100`
（少插一个 -100 时，剩下的仍全是 -100，只看"有 -100"会漏判）。

连带修正：`armfstest.sh` 的"共 3 次"判据改为 4 次（unlink 现在也记日志）。

## 五、已知限制 / 下一步

- **这只是地基**，还不是包管理器。示例操作的是**写死的路径**，没有清单解析、
  依赖解析、版本锁定。
- **没有 git**：安卓原生没有 git，包分发得换成文件或网络协议。
- **`stat` 只断言返回值**，不解析 `struct stat` —— `cfs-*` 走 C 生成器，
  没有 `load8` 映射，读不了结构体。
- **清单解析需要逐字节访问**，同样受限于 `load8`。要真做包解析，
  得先给 `cfs-*` 后端补 `load8`（编译器级改动，自举 hash 会变）。

下一步最有杠杆的是给 `cfs-*` 后端补 `load8` —— 补上之后包清单解析、
哈希校验都能在安卓上跑，那时才谈得上真正的包管理器。
