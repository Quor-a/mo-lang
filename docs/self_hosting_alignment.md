# 自举对齐：seed 与 compiler.mo 必须严格一致

## 结论

墨语言有两个编译器实现：

| 实现 | 语言 | 位置 |
|---|---|---|
| **seed** | 手写 x86-64 汇编 | `src/asm/*.s` |
| **moc** | 墨语言自己 | `src/mo/compiler_part{1..5}.mo` |

self-hosting 要求：**两者编译同一个 compiler.mo，必须产出字节相同的 moc。**

这意味着——**任何改变"编译期副作用"的改动，都必须同时改两边。**

## 一个真实的踩坑

在 compiler.mo 的 `main()` 里新增 `dquad()` 调用（往输出数据段写东西），
自举立即失败：

```
seed 编译 → m1   数据段 3576
m1 编译   → m2   数据段 3608     差 32
```

### 定位

对比 m1 / m2 的代码段，首个不同在偏移 67：

```
m1: movabs $0x10000010, %r11     ← 全局变量从数据段偏移 16 开始
m2: movabs $0x10000030, %r11     ← 全局变量从数据段偏移 48 开始
```

**全局变量地址不同。**

### 根因

seed 在 `src/asm/main.s` 里**写死了**数据段头的布局：

```asm
call emit_startup
xorq %rdi, %rdi
call dquad          # argc
xorq %rdi, %rdi
call dquad          # argv
call parse_program
```

compiler.mo 那边是 `reserve_arg_slots()`，写 34 个 dquad。

我只改了 compiler.mo，没改 seed 的汇编 → 两边对数据段头的
认识差 32 字节 → 全局变量地址不同 → 代码不同 → 不自举。

**同步改 seed 的汇编后，自举立即一致。**

### 这不是 seed 的 bug

我一度判断为"seed 有缺陷、信任根动摇"。**这个判断是错的。**

seed 是手写汇编的最小引导编译器，那段逻辑本来就写死在汇编里。
compiler.mo 改了布局，seed 当然要跟着改——这是自举编译器的
**固有约束**，不是缺陷。

## 规则

改动 compiler.mo 时，若影响了以下任一项，**必须同步 `src/asm/main.s`**：

- 数据段头的 dquad 数量（argc/argv / 参数暂存区 / 任何预留）
- `emit_startup` 的结构
- 输出段的顺序与数量

判断方法很简单：**改完跑 `make boot`**。若 Stage1 ≠ Stage2，
先怀疑是不是漏改了 seed。

## 顺带确认的一点

seed 只实现了编译 compiler.mo 所需的语法子集。例如它不支持
全局数组初始化（`var A: [8] i64 = 0;` 会报 syntax error），
而 moc 支持。

所以 seed 与 moc **本来就不是等价的两个实现**：
seed 是"刚好够用"的引导器，moc 才是完整编译器。
自举一致只说明**当前 compiler.mo 这条路径上两者吻合**。

## 自动检查

`make seedalign`（已接入 `make all`，在 boot 之前跑）：

```
seedalign: OK (数据段头 dquad: seed=34, compiler.mo=34)
```

不对齐时：

```
seedalign: ✗ 不对齐
    src/asm/main.s            : 33 个 dquad
    src/mo/compiler_part5.mo  : 34 个 dquad
    ...
```

脚本在**编译之前**拦下漏改，省掉一轮"自举失败 → 二分排查"。

我为此花过整一轮时间，还一度误判成"seed 有缺陷、信任根动摇"。
有这个检查后，同样的问题会在 1 秒内暴露并给出原因。

## seed 补上复合赋值（1.68.0）

### 为什么值得做

1.67.0 加了「复合赋值 `/=` `%=` 的强度削减」，但 **seed 完全不支持复合赋值**
（compiler.mo 自身也不用），所以 `make boot` 虽然通过，这项优化**根本不在
自举验证范围内** —— 是 `tests/98` 的穷举在兜底。

这次补上三件事：

1. seed 词法识别 `+= -= *= /= %= &= |= ^=`
2. seed 语句层实现复合赋值（含 2 的幂与魔数两条强度削减路径）
3. **compiler.mo 真正用上复合赋值**（6 处 part1 + 4 处 part2 + 3 处 part5）

第 3 点是关键：只做前两步的话，seed 编译 compiler.mo 依然不走这条路径，
自举照样验证不到。**自举只覆盖「被测到的路径」，要让一条路径被覆盖，
必须让 compiler.mo 真的用到它。**

### 变异测试：证明覆盖是真的

故意把 seed 侧 `/=` 的魔数路径退回 idiv：

```
❌ 自举不一致
```

自举**立刻**失败。这证明覆盖非空转 —— 否则改了也没反应。

（对照：如果不改 compiler.mo 只用 tests/98 兜底，同样的变异不会让
`make boot` 失败，只会在跑 98 时暴露。）

### 🔴 一个我自己制造的流程事故

中途测到「seed 编译小程序段错误」，我以为是改动破坏了 seed，于是回退
lex.s 和 stmt.s —— 结果**仍然失败**，越查越乱。

真正原因：**测试文件被 `make bin/moc` 清理了**（`build.sh self` 里有
`rm -rf /tmp/mobuild`），seed 报 `cannot open input`，退出码非 0 而我没看
stderr，只看了结果。

更糟的是我一度把 "产物 4368 字节" 当成"只生成了骨架"，**其实那就是
最小程序的正常大小** —— 我先入为主地认为它不正常，于是整轮判断都跑偏了。

> 判断"异常"之前先确认"正常"长什么样。没有基准就说某值异常，是把假设当证据。

修法：`tools/seedsmoke.sh`（`make seedsmoke`）自带测试文件，不依赖外部残留，
秒级确认 seed 基本可用。**改 seed 后先跑它，再跑 boot。**

### 一处实现细节

compound_op 的 op 编号复用了 `256(%rsp)`（原本是 if/while 的 label A 槽）——
两者互斥，所以安全，且**不必改动栈帧大小**。

第一版我把栈从 288 加到 296 来新增槽位，而 296 不是 16 的倍数，会破坏栈对齐。
规避掉了，但值得记一笔：**给汇编函数加栈槽时注意 16 字节对齐。**
