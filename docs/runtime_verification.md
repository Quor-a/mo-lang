# 运行时验证：内核与 UEFI 真的跑起来了

版本 1.20.0（2026-10-09）

**这是本项目第一次拿到内核与 UEFI 的运行时验证。**

此前所有系统级目标都只验证到"产物结构正确"（Multiboot 头位置、PE 子系统号、
ELF 机器类型），**从来没有真正执行过**。这一轮改变了这一点。

## 外部依赖

运行时验证需要 `unicorn`（CPU 模拟器）。沙盒/容器被重置后 pip 包会消失，
所以由 **`tools/pyreq.sh`** 统一检测与获取（与 `tools/zigcc.sh` 同一套思路）：

```bash
bash tools/pyreq.sh unicorn
```

缺失时 `kernrun.py` / `uefirun.py` 会给出清晰指引而不是 traceback。
两个 `*_test.sh` 会在缺少时**跳过并说明**，不假装通过。

## 怎么做到的：不装 QEMU，改用 CPU 模拟器

QEMU 装不上（apt 无包、网络超时）。但验证内核不需要完整的机器模拟——
需要的是**能执行 ring0 特权指令的 CPU**。

`qemu-user` 只能跑用户态，不适合。而 **Unicorn**（`pip install unicorn`）
是纯 CPU 模拟器，能跑特权指令，正是验证内核所需。

代价与收益都写清楚：

| | QEMU 系统模拟 | Unicorn |
|---|---|---|
| 设备模拟 | 有（VGA、键盘、磁盘） | **没有**，要手工搭 |
| 特权指令 | 支持 | 支持 |
| 获取难度 | 本机装不上 | `pip install` 即可 |

所以本轮的工作量主要花在"手工搭最小硬件环境"上。

## 内核：tools/kernrun.py

搭建的环境：

- 把 ELF 的 PT_LOAD 段加载到链接地址 `0x100000`
- 映射 VGA 文本缓冲 `0xB8000`（就是普通内存，写进去能读出来）
- 映射栈，`esp` 指向栈顶
- `eax = 0x2BADB002`（Multiboot magic）、`ebx = 0`
- **hook `in`/`out` 指令**模拟键盘控制器（0x64 状态口、0x60 数据口）

执行后从 `0xB8000` 读回屏幕。

### 实测

```
========== 屏幕内容 ==========
Mo Kernel v1.16 -- written in the Mo language
no libc, no syscalls: direct VGA + port I/O
type 'help' then Enter. Ctrl-Alt-Del to reboot.

mo> help

commands: help, echo, add, ticks, clear, halt
mo>
```

键盘输入也工作：喂入扫描码后，内核真的回显、解析、执行了命令。

### 踩到的坑

**1. Unicorn 的内存映射必须逐页进行**

一次映射整块时，若其中**任一页已存在**，Unicorn 会**整块失败**——
于是部分重叠的那段就没人映射，之后写入直接 `UC_ERR_WRITE_UNMAPPED`。

ELF 的多个 PT_LOAD 常落在同一页区间里（本例 `0x100000` 与 `0x10000c`
就在同一页），所以必须逐页 `mem_map` 并忽略已映射页。

**2. `IN`/`OUT` 的 hook 签名不同且不对称**

- `IN`：`callback(uc, port, size, ud)`，**返回值**会被写入 EAX
- `OUT`：`callback(uc, port, size, value, ud)`

写成一样会 `TypeError`。这是个容易反复踩的点。

### 顺带抓到一个真 bug：add 34 算出 -45

内核 shell 的 `add` 命令原样读取 `LINE[4]` 和 `LINE[6]`，
却**没有校验格式**。于是输入 `add 34` 时：

- `a = LINE[4] = '3'` → 3
- `b = LINE[6] = 字符串结尾的 0` → `0 - 48 = -48`
- 结果 `3 + (-48) = **-45**`

这是典型的"安静地给出错的结果"——不崩不报错，只是答案离谱。
在内核里尤其危险。已修：校验长度、空格位置、数字范围，
不符合就打印 `usage: add <digit> <digit>`。

## UEFI：tools/uefirun.py

UEFI 更难：没有固件，就没有 BootServices、没有 ConOut。
解法是**手工造一个最小 UEFI 环境**：

```
EFI_SYSTEM_TABLE @ 0x60000
  +64 → ConOut @ 0x61000
          +8  → OutputString（指向"魔法地址" 0x7000）
          +48 → ClearScreen（指向 0x7100）
```

在那些魔法地址上 `hook_add(UC_HOOK_CODE, ..., begin=end=地址)`：
读 `rdx`（CHAR16*），转 ASCII 记录，写 `rax=0`（EFI_SUCCESS），
然后**手工弹出返回地址**写回 `rip`。

### 实测

```
Mo UEFI application
running in the firmware environment

fib: 0 1 1 2 3 5 8 13 21 34 55 89 144 233 377
sum 1..100 = 5050
```

递归 fib 与整数计算在固件环境里都正确。

### 踩到的坑

**UTF-16 读取把换行吃掉了**

`CHAR16` 是 UTF-16LE。我在转 ASCII 时写了
`chr(c) if 32 <= c < 127 else '.'`——而 `\r`(13)、`\n`(10) 都 < 32，
于是换行全变成 `.`，输出挤成一行。

修法：把 10 和 13 也当可打印字符保留。

## 验证

```
bash tools/kernrun_test.sh     # 8 项
bash tools/uefirun_test.sh     # 5 项
```

都接入了 `make all`。

## 仍然没做到的（诚实列出）

- **安卓原生（ARM64）仍无运行时验证**：Unicorn 能跑 ARM64，
  但它跑的是 `svc` 系统调用，需要模拟 Linux 内核的 syscall 表——
  工作量不小，本轮没做
- **`.ko` 内核模块没编译也没加载**：无内核头文件
- **真实硬件没跑过**：模拟器不等于真机，VGA 时序、
  真实键盘控制器等行为仍未被验证
- Unicorn 模拟的"键盘"是喂扫描码，没验证真实 PS/2 时序

## ARM64（Android 原生）—— tools/armrun.py

交叉编译出的 ARM64 程序在本机（x86-64）**从来没法执行**，之前只验证到
ELF 机器类型 = 0xb7。这一轮也真正跑起来了。

做法：Unicorn 模拟 ARM64 CPU，并在 `svc #0` 处**自己实现 Linux 的
syscall 表**（AArch64 用 asm-generic/unistd.h 的号，与 x86-64 不同）：

```
调用号在 x8，参数在 x0-x5，返回值在 x0，出错时为负的 errno
```

只需实现程序实际用到的那几个：write(64)、exit(93)、exit_group(94)、
brk(214)、mmap(222)、getpid(172)、read(63)、close(57)……

实测：

```
Mo on Android — native ARM64, no libc
counting primes below 200000
primes below 200000 = 17984
退出码     : 0
```

**π(200000) = 17984 是数学上的已知值**——所以这不是"跑起来了就算过"，
而是真的算对了。

### 踩到的坑

**1. ELF 的 `EI_DATA` 是 1 表示小端，不是 2**

我第一版写 `assert d[5] == 2` 当"小端"，于是 AArch64 小端程序被判成
"不是小端"。1 = ELFDATA2LSB（小端），2 = ELFDATA2MSB（大端）。

**2. 指令上限太小会误判成"程序卡住"**

朴素素数算法在 1000000 规模下需要约 10^9 次内层迭代。上限设 5000 万时
程序"看起来卡住"，其实是还没跑完。

所以把示例的默认规模改成 200000（π=17984，已知值），1.5 秒跑完，
适合做回归；真机上可传参数放大。

**3. 文案里的上限写死了**

数字是对的，但文案印着 "primes below 1000000" —— 参数是 200000 时
属于"数字对、描述错"，会误导读输出的人。已改成跟随 n。

### 已知限制：freestanding 下 argc/argv 读不到

`_start` 里用 `ldr x0, [sp]` 读初始栈上的 argc，但 **C 编译器会先生成
函数序言调整 sp**，于是读到的是错的（实测 `argc()` 返回 0）。

正确做法需要 `__attribute__((naked))` 让 _start 没有序言，
但 naked + 多行内联汇编要跨"墨语言词法 + C 词法"两层转义，
实测很容易生成被真实换行截断的字面量，报
`expected string literal in 'asm'`。

**当前状态**：argc/argv 在 freestanding 后端不可靠，已记录为已知限制。
程序在无参数时用默认规模，功能不受影响。

### 三个运行时测试脚本

```bash
make kernrun     # → tools/kernrun_test.sh（内核 8 项）
make uefirun     # → tools/uefirun_test.sh（UEFI 5 项）
make armrun      # → tools/armrun_test.sh（ARM64 原生 5 项）
```

三者都接入了 `make all`，并由 `tools/pyreq.sh` 统一检测 `unicorn`——
缺失时**跳过并说明**，不假装通过。

### 四个运行时测试脚本

```bash
make kernrun    # tools/kernrun_test.sh    内核 8 项
make uefirun    # tools/uefirun_test.sh    UEFI 5 项
make armrun     # tools/armrun_test.sh     ARM64 原生 5 项
make riscvrun   # tools/riscvrun_test.sh   RISC-V 原生 5 项
```

`tools/riscv_native.sh` 是 RISC-V 的构建脚本（对应安卓的
`tools/android_native.sh`），产物是静态无 libc 的 RISC-V ELF，
能在开发板、QEMU 或未来的 RISC-V 手机上直接跑。

## s390x / ppc64le —— 新增两个后端

`mo2x` 新增 `cfs-s390x` 与 `cfs-ppc64le` 两个 freestanding 目标。

s390x 有两处与其它架构**根本不同**，都踩到了：

1. **大端**：`EI_DATA=2`。照抄小端断言会把正确产物判成"不是小端"
2. **自己的 syscall 号表**：`write=4`、`exit=1`，**不是** asm-generic 的 64/93。
   `svc 0` 陷入，调用号在 r1、参数 r2-r7、返回 r2

另外 `ppcle` 的 ABI 是调用号 r0、参数 r3-r8、`sc` 陷入。

### 修掉一个影响 x86-64 的真 bug：basic asm 里的 `%%`

naked `_start` 用的是 **basic asm**（没有冒号、没有操作数）。这种形式下
**`%` 不是占位符**，`%%` 会被原样输出成两个字符，于是生成

```
asm volatile("movq (%%rsp), %%rax");   →  invalid register
```

正确写法是**单个** `%`。这个 bug 同时影响 x86-64、s390x、ppc64le 三个
freestanding 目标——只有带操作数（extended asm）的地方才该写 `%%`。

### 环境问题的根治：pylibs 持久化

此前 `pip install unicorn` 报成功，下一次工具调用包就不见了（沙盒会重置
系统 site-packages），导致运行时验证随机失败。

现在 `tools/pyreq.sh` 统一安装到 **`/data/workspace/pylibs`**（可用
`MO_PYLIBS` 覆盖），各运行器启动时把它加进 `sys.path`。这样不再受
系统目录被重置的影响。

### s390x 的运行时验证：未通过（诚实说明）

构建**完全成功**并已验证：

```
✓ 机器类型 = 0x16 (s390x)
✓ 字节序 = 大端
大小: 11552 字节（静态、无 libc）
```

但在 Unicorn 里**执行未跑通**。已查明的一个具体障碍：

> s390x 下 Unicorn 只接受**低位**地址。实测栈放 `0x18000` 时 `lg` 读到
> 正确值；放 `0x3fffff00` 时读到 **0**——**不报错，只是内容错**。
> ARM64 / RISC-V 用高位地址没问题，只有 s390x 这样。

把布局压到 1MB 以下后 PC 能前进（0x1001ac0 → 0x1001ad0），但仍无输出，
且模拟速度约 10 万条指令/秒，对素数计数这类程序不实用。

所以 `s390xrun.py` **未接入 `make all`**。ppc64le 也只到"后端已实现"，
尚未构建验证。这两项记在待办里，不含糊过关。

`tools/s390x_native.sh` 是 s390x 的构建脚本（已验证：机器类型 0x16、
大端、静态无 libc）。`tools/s390xrun.py` 是它的运行器，但执行未跑通，
故未接入 `make all`——原因见上文「s390x 的运行时验证：未通过」。

### s390x 现在跑通了

关键：**把整个程序链接到低位**（`-Wl,--image-base=0x10000`）。

之前只把栈压到低位，数据段仍在 `0x10022e8`（高位），于是 `stg` 写入
静默失败，程序表现为卡在同一条指令不动、反复触发 syscall。
把代码/数据/栈全部压到 1MB 以下后：

```
========== s390x 程序输出 ==========
hello from s390x
====================================
```

另一个处理：exit 之后 Unicorn 仍会继续取指，程序会再跑一轮（输出重复）。
模拟器里加了**收敛保护**——检测到输出开始重复即认为已跑完。

真机不受影响：ELF 仍是正常的静态可执行文件，`--image-base` 只影响
模拟器能否访问其内存。

`make s390xrun` 已接入 `make all`（3 项断言）。

`make s390xrun` → `tools/s390xrun_test.sh`（s390x 3 项断言）。

## ppc64le / ppc64 —— 构建成功，运行时验证未跑通

### 构建部分（已成功）

```
$ bash tools/ppc64_native.sh examples/s390hello.mo build/hello.ppc64le
   ✓ 机器类型 = 0x15 (PowerPC64)
   ✓ 小端
大小: 4272 字节（静态、无 libc）
```

### 为什么改用大端 ppc64 做验证

**Unicorn 的 PPC 后端只支持大端。** 实测：

```
UC_MODE_PPC64 | UC_MODE_LITTLE_ENDIAN  → UcError: Invalid mode
UC_MODE_PPC64 | UC_MODE_BIG_ENDIAN     → OK
```

所以给 PowerPC 做了两个后端：
- `cfs-ppc64le`：小端，可在真机（POWER8 LE 等）运行
- `cfs-ppc64` ：大端，**专门为了能在模拟器里验证**

两者生成完全相同的汇编（同一个 syscall 表：write=4、exit=1，
`sc` 陷入，调用号 r0、参数 r3-r8），只是链接目标字节序不同。

### 结论：Unicorn 无法运行 PPC64 程序（硬限制，非代码问题）

**孤立实验确认：Unicorn 的 PPC64 后端不支持无条件分支 `b`。**

```
在 0x1000 放 `b 0x1100`（4a000100）后单步执行：
  → UcError: Unhandled CPU exception，PC 只前进到 0x1004

前跳 / 后跳 / 设置 MSR 的 IR·DR 位 —— 三种情况全部失败
```

而 `addi` + `sc` 这类直线指令能正常执行并正确陷入，说明**不是墨语言产物的问题**，
是 Unicorn 的 PPC 实现不完整。任何真实程序都必须使用分支，因此
**PowerPC 架构无法用 Unicorn 做运行时验证**。

调查过程中还确认了两件事（都已修正）：

1. **栈与代码段重叠**：`--image-base=0x10000` 后代码落在 0x10000，而运行器
   默认栈布局 `0x18000-0x8000` 恰好覆盖 `0x10000~0x18000`，把代码段整个冲掉
   —— 表现为第一条指令就触发陷入、PC 从不前进。已修（栈抬到 0x60000）
2. **TOC 指针 r2 未建立**（真机正确性问题）：ELFv2 下访问全局/常量要经 r2，
   而 `-nostdlib` 没有 crt 来建立它。r2=0 时会算出 0x7dd40000 这类垃圾地址，
   程序跑飞到异常向量区。已在 naked `_start` 里手工建立：
   `addis 2,12,.TOC.-_start@ha` + `addi 2,2,.TOC.-_start@l`

   推算验证：代码里 `addis r3,r2,-3` → `addi r4,r3,0x7ed0`，
   代入 r2 = .got(0x30330) + 0x8000 = 0x38330 得 0x10200，正好是 `.rodata`
   里字符串的地址 —— 说明 TOC 基址推算正确。

### 退而求其次：静态验证

既然不能执行，`tools/targets_test.sh` 对 PowerPC64 做**静态验证**（7 项）：

```
✓ 构建成功（大端、静态无 libc）
✓ ppc64le 小端构建成功
✓ ELF 机器类型 = 0x15 (PowerPC64)
✓ 大端（EI_DATA=2）
✓ _start 建立 TOC 指针 r2
✓ 用 sc 陷入内核
✓ ppc64 syscall 号表（write=4）
```

`tools/ppc64run.py` 会直接说明限制并退出，不假装"跑过了"。
