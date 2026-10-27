# codecompose —— 代码段体积构成（墨语言版）

`tools/codecompose.mo` → `bin/codecompose`，取代 `tools/codecompose.py`。

## 为什么不借 objdump

原版流程：`readelf -lW` 找可执行 LOAD 段 → 抠成裸二进制 → `objdump -D` 反汇编 →
按助记符分组。反汇编这件事完全交给 objdump 这个黑盒：它说某条是 mov 就是 mov，
没人验证过它扫得对不对。

本版：自己解析 ELF 程序头 + 自己写 x86-64 指令长度解码器 + 自己按 opcode 归类。
全程不调外部工具，因此可以断言 **线性扫描的指令边界必须精确落在代码段末尾** ——
任何一条指令长度算错，末尾就对不上。这是对"扫描本身"的校验，objdump 版做不到。

## 🔴 口径：可执行段 ≠ 代码

链接器产出的 PT_LOAD(RX) 从文件偏移 0 开始，前面是 **ELF 头 + 程序头表**，
后面是**对齐到 0x1000 的零填充**（bin/moc 上共 810 字节）。两者都不是代码。

- 从偏移 0 扫会把 `7f 45 4c 46`（`\x7fELF`）当指令解 —— 第一版就中了这招，
  `-u` 里冒出一堆计数为 1 的怪 opcode（`0xcd int` / `0xef out` / `0xe4 in`）
- 尾部的 0x00 是合法的 `add %al,(%rax)`，不剔除会被当成 634 条指令计入 arith

现在从**入口点**开始扫，到最后一个非零字节结束。

## 🔴 两个共有的解码器 bug（dwmo.mo 也有）

| bug | 后果 |
|---|---|
| `mod == 3` 未处理 | 寄存器直接寻址既无 SIB 也无 disp。少了它，每条 `48 81 ec imm32`（sub rsp,N）多算 1 字节，墨语言每个函数序言都有它 → 整体错位 |
| group3 (0xf6/0xf7) 立即数 | 只有 `/0 /1`（test）带 imm，`div/idiv/mul/neg/not` 不带。无条件加 4 字节 → 每条 idiv 后错位 4 字节 |

验证方式：与 objdump 逐条比对指令边界。修复前 597 处分歧，修复后 0 处（43808 条）。
两个 bug 都不报错，只是悄悄解出乱指令。

## 🔴 Python 版一直在少算字节

objdump 一行最多打印 7 字节，movabs 是 10 字节，多出的 3 字节在折行里，
Python 版的正则取不到。于是 1865 条 movabs **每条只算 7 字节**：
13055 vs 正确值 18650，总量少算 5459 字节。

指纹：旧报告里 "movabs 均长 7.00"。真值恒为 **10.00**（1 操作码 + 8 立即数）。
`tools/motools_test.sh` 把这条写成不变量，并加了"必须有 movabs"的守卫
（否则断言会在没有 movabs 时空转成 0==0 通过）。

## 用法

```bash
./bin/moc tools/codecompose.mo build/codecompose.elf
./build/codecompose.elf bin/moc        # 统计表
./build/codecompose.elf bin/moc -u     # 列出 other 桶的 opcode 构成
./build/codecompose.elf bin/moc -t     # 逐条打印 offset / 长度 / 类别
```

## 结论（bin/moc，142550 字节 / 43808 条）

push+pop 合计 18.2%，均长 **1.64** 字节。`pop rcx` 1 字节、`push rax` 1 字节，
而寄存器传送 `mov rcx,rbx` 要 3 字节 —— 所以**寄存器分配会增大体积**，
方向跟"省 30%"正好相反。
