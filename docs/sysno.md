# syscall 号翻译：freestanding 后端的架构级静默缺陷

版本 1.153.0（2026-10-22）—— 1.152 只翻译了号；1.153 补上 *at 适配、
栈对齐缺陷，以及构建失败复用旧产物的验证陷阱

## 一、缺陷

墨语言源码里的 `syscall(n, ...)` 用的是 **x86-64 号表**（`open=2`）。
`mo2x` 此前把它**原样透传**给所有 freestanding 后端：

```
源码        syscall(2, path, flags, mode, 0,0,0)   # x86-64: open
cfs-aarch64 → mo_syscall(2, ...) → svc #0, x8=2    # ARM64:  io_submit
cfs-x86_64  → mo_syscall(2, ...) → syscall, rax=2  # x86-64: open
```

两个架构生成**完全相同的号码**。ARM64 的 2 号是 `io_submit`，
与 `open` 毫无关系。

**不报错、不崩溃**，只是发了一个完全不相干的系统调用
（通常返回 `-ENOSYS`，或碰巧做了别的事）。

## 二、为什么此前从未被抓到

`print()` 走的是 `emit_fs_print()`，它用的是架构正确的
`MO_WRITE_` / `MO_EXIT_` 宏 —— **绕开了这条路径**。

而所有 freestanding 示例（`andromo.mo`、`s390hello.mo`、
`kernel.mo`、`uefi.mo`）都只打印、不读写文件，
`syscall()` 出现次数为 **0**：

```
examples/s390hello.mo: 0
examples/kernel.mo:     0
examples/andromo.mo:    0
examples/uefi.mo:       0
```

所以这条路径的覆盖率是零 —— 样本看着在跑，实际一行都没执行过。
（与 v1.141 SAM 的 `SA_NCL=0`、v1.144 sketch 的 `w=200` 同类：
**样本充分 ≠ 覆盖充分**。）

## 三、修法

在 `tools/mo2x.mo` 的 `syscall` 发射处，对**第一个参数**
（调用号）做翻译：

- 整数字面量 → 查 `fs_sysno()` 按目标架构换号
- `aarch64` / `riscv64` 共用 asm-generic 表
- `x86-64` 原样输出（源码写的就是它）
- 其余架构返回 `-2` → 报错

### 参数形态不同的调用：1.152 报错，1.153 改为自动适配

`open` / `stat` / `mkdir` / `unlink` 在 ARM64 只有 `*at` 版本
（`openat(56)`），**参数个数与含义都不同**。换号会静默给出错误语义，
所以返回 `-1` 让发射处**响亮报错**：

```
mo2x: /tmp/sysext.mo:5: syscall 号不能只靠换号翻译：
      open/stat/mkdir/unlink 在目标架构是 *at 版本，参数不同
退出码 = 1
```

宁可构建失败，也不要在手机上发错调用。

### 已翻译的号（asm-generic）

| 语义 | x86-64 | aarch64 / riscv64 |
|---|---|---|
| read | 0 | 63 |
| write | 1 | 64 |
| close | 3 | 57 |
| lseek | 8 | 62 |
| brk | 12 | 214 |
| execve | 59 | 221 |
| exit | 60 | 93 |
| wait4 | 61 | 260 |
| getdents64 | 217 | 217 |
| exit_group | 231 | 94 |

## 四、验证

端到端，在 Unicorn 模拟器里**真跑** ARM64 程序：

```mo
fn main() -> i64 {
    syscall(1, 1, "MO-ARM64-SYSNO-OK\n", 18, 0, 0, 0);
    syscall(60, 0, 0, 0, 0, 0, 0);
    return 0;
}
```

生成的调用号：`mo_syscall(64, ...)` / `mo_syscall(93, ...)`。

```
========== ARM64 程序输出 ==========
MO-ARM64-SYSNO-OK
退出码 : 0
```

翻译前发的是 `x8=1`（`io_setup`）→ **静默无输出**；
翻译后发 `x8=64`（`write`）→ 真的打印出来了。

回归：aarch64 / s390x / ppc64 / riscv64 四个目标的现有构建
全部成功，产物大小不变。

## 五、踩到的坑（我自己犯的）

用管道测退出码：

```bash
./bin/mo2x ... 2>&1 | tail -6; echo "退出码=$?"   # 取的是 tail 的，恒为 0
```

一度以为 `err()` 返回 0、修复没生效。实际 `err()` 早就 `exit(1)`。
这与 v1.132 记过的是**同一个坑**，重写时又犯了一次。

## 六、已知限制（都没静默）

- `open` / `stat` / `mkdir` / `unlink` 在 aarch64 **暂不可用**
  （报错退出码 1，不静默）
- **变量形式的调用号无法翻译**：`syscall(k, ...)` 里 `k` 是变量时，
  仍按原号透传 —— 在 aarch64 上依旧会发错。这是当前最危险的遗留项
- `s390x` / `ppc64` 暂无号表（返回 -2 报错）

## 七、对"安卓包管理器"的意义

包管理器必须读写文件（`mo.toml`、锁文件、建目录）。
在这个缺陷修好之前，**它在 ARM64 上所有文件操作都会发错号** ——
而这正是"能在安卓上跑"的地基。


---

## 八、1.153：把「报错」变成「真的能用」

### *at 参数重排

| x86-64 语义 | 号 | aarch64 | 形态变化 |
|---|---|---|---|
| open | 2 | 56 openat | 号后**插入** dfd = AT_FDCWD(-100) |
| mkdir | 83 | 34 mkdirat | 同 |
| unlink | 87 | 35 unlinkat | 同 |
| stat | 4 | 79 newfstatat | 插入 dfd + **尾部追加** flags |
| access | 21 | 48 faccessat | 同 |

插入 dfd 后实参多一个，所以**源码里的占位实参要少写一个**，否则适配后
超出 `mo_syscall` 的 7 个形参 → 编译失败（已写进 CLAUDE.md 第 13 条）。

### 🔴 顺带挖出的缺陷：cfs-x86_64 的 _start 栈错位 8 字节

用到**局部数组**的程序在 x86-64 上一启动就 SIGSEGV —— 崩在任何输出之前，
看起来完全像「程序没运行」。数组被优化掉的程序一切正常，极难归因。

守护它的是 `examples/armfs.mo` 里的 `let buf: [32] i64`：**故意**用局部数组。

### 端到端：ARM64（模拟器）× x86-64（真机）双端对照

`tools/armfstest.sh`，19 项断言：

```
write bytes = 9      read bytes  = 9      read back   : MO-FS-OK
mkdir ret   = 0      unlink ret  = 0
openat/mkdirat 调用 : 3        （三次首参全是 dfd=-100）
真机: /tmp/mo_armfs_dir 确实存在 / unlink 后文件确实没了
```

A 端用 Unicorn 模拟 ARM64 CPU + 自制 syscall 表（内存文件系统），
B 端在本机跑**真**文件系统。**只跑一端，三个变异里有两个会漏**：

| 变异 | ARM64 端 | x86-64 端 |
|---|---|---|
| M1 不插入 AT_FDCWD(-100) | — | 红 |
| M2 open 不换号（2→56） | 红 | — |
| M3 去掉 _start 栈对齐 | — | 红 |

### 🔴🔴 本轮最有价值：验证脚本在构建失败时跑的是旧产物

`armfstest.sh` 第一版没有 `rm -f $OUT`，构建失败后 `if [ -x $OUT ]` 仍成立
—— 于是执行的是**上一个版本**的二进制，判据全绿，M1 被打印成「未被捕获」。

手工单跑却是红的（那时产物恰好被覆盖），脚本里却稳定复现为绿。
这类「结论随环境漂移」的现象，第一反应不该是放宽断言，而是查
**产物是不是新的**。

修法：测试开头 `rm -f $OUT`；构建退出码单独判；失败即 `fail+=1` **并跳过执行**。
这与 v1.153 记过的「源码干净 ≠ 产物干净」是同一个坑的另一半。

现 `tools/armfsmut.sh` 三个变异全部被捕获（4 / 7 / 8 项变红）。

### 已知限制（新增）

- `load8` / `store8` 在 `cfs-*` 后端**没有映射**（原生后端才有），用了直接
  编译失败。要校验读回的字节，把它 **write 回 stdout 让脚本 grep**。
- 模拟器里的文件系统是**内存**的（armrun.py 自实现），不是真内核；
  所以必须再用 x86-64 真机端交叉确认，否则判据只证明了模拟器迁就实现。
- `stat` / `access` 的 flags 尾参是**追加 0**，未按 x86 语义映射。
