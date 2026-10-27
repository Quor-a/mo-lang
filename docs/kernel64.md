# ARM64 裸机内核（kern-aarch64）

版本 1.162.0

一句话：**墨语言现在有两个内核，第二个跑在 ARM64 上。**

`examples/kernel.mo` 是 x86 Multiboot 内核（VGA + 端口 I/O），
`examples/kernel64.mo` 是 ARM64 裸机内核（PL011 UART MMIO）。

```bash
bash tools/kernel64.sh examples/kernel64.mo /tmp/mokern64.elf   # 构建
python3 tools/kern64run.py /tmp/mokern64.elf                    # 在模拟器里真跑
bash tools/kern64test.sh                                        # 端到端断言
bash tools/kern64mut.sh                                         # 变异验证
```

## 与 x86 内核后端差在哪

不是"换个地址"这种小改动，是**硬件模型的差别**：

|          | x86 内核（kern）        | ARM64 内核（kern-aarch64）   |
|----------|-------------------------|------------------------------|
| 输出     | VGA 文本缓冲 `0xB8000`  | PL011 UART MMIO `0x09000000` |
| 输入     | `in`/`out` 端口读键盘   | 同一块 UART 的 MMIO 读       |
| I/O 空间 | 有（独立端口地址空间）  | **无**，一切皆 MMIO          |
| 停机     | `hlt`                   | `wfi`                        |
| 引导     | Multiboot1（GRUB/QEMU） | ELF 直接加载（QEMU virt）    |

最要紧的一条：**ARM64 没有 I/O 地址空间**。x86 的 `inb/outb` 在 ARM64 上
只能退化成 MMIO 字节读写 —— 所以源码里那些 x86 端口号在 ARM64 上不成立，
键盘那类设备必须改走 UART。这不是能靠"翻译调用号"糊过去的事。

## 内核下面什么都没有

验证用的 `tools/kern64run.py` 与 `tools/armrun.py` 是两种东西：

- `armrun.py` 实现的是 **Linux 系统调用表**（在 `svc #0` 处接住）
- `kern64run.py` 实现的是 **硬件**（把写往 UART 数据寄存器的字节收成控制台输出）

也就是说后者**内核下面没有 Linux、没有 libc、没有 Android**，只有一块
CPU 和一个串口。机器起来后自己打印、自己算、自己停机，就算成立。

实测输出：

```
MO-KERN64 BOOT
arch=aarch64  console=mmio-uart@0x09000000
no libc / no syscall / no host os
selftest:
  [1] got=55 want=55  OK
  [2] got=5050 want=5050  OK
  [3] got=6765 want=6765  OK
selftest passed: 3/3
MO-KERN64 HALT
```

## 三个坑（全都是静默的）

**一、ELF 头字段偏移按"连续排列"猜，读出 `e_phnum=0`。**
于是**一个 PT_LOAD 都没加载**，程序从全 0 的内存起跑，第一条指令是
`udf #0`，模拟器报异常、输出为空。看着像"内核跑挂了"，其实是加载器
静默失败。ELF64 的正确偏移是 `e_entry@0x18 / e_phoff@0x20 /
e_phentsize@0x36 / e_phnum@0x38`。

**二、Makefile 里 `bin/mo2x` 只依赖 `$(MOC)`，不依赖 `tools/mo2x.mo`。**
改了转译器源码**不会重建**，于是新后端永远是死代码。已补上依赖。
这是 v1.154 记过的同类问题（`$(MO2X)` 变量未定义）换了个地方再犯。

**三、中文引号写进了 C 字符串字面量。**
`line("/* 裸机没有"退出到谁"这一说 */")` 里的引号提前闭合了墨语言的
字符串，报的是 `syntax error`，行列还指向别处。

## 变异验证（证明不是空转）

| 变异 | 结果 |
|---|---|
| M1 UART 基址 `0x09000000` → `0x08000000` | ✅ 捕获（内核照跑，只是往错误地址写、输出消失） |
| M2 aarch64 不分派、落到 x86 VGA 前导 | ✅ 捕获 |

M2 尤其重要：拿错前导时产物**照样编得出来、链得起来**，只是往 `0xB8000`
写 —— 在模拟器里无声无息。测试里那条 `ckhasnot 0xB8000` 是专门盯它的。

## 已知限制

- **没有中断、没有 MMU、单核** —— 裸机内核的最小形态，只有轮询式 UART
- UART 基址 `0x09000000` 是 QEMU virt 的约定；别的板子要改前导里那一行
- 内核示例不做输入（模拟器里 `stdin` 无从谈起），`uart_getc` 已在前导里
  提供但本轮未端到端验证
- 停机是 `wfi` 空转，所以模拟器里"跑满步数"即正常结束，不是异常
- 未经真实硬件验证，只在 CPU 模拟器里跑过
