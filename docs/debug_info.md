# 调试信息（-g）：行号与变量位置

```bash
./bin/moc prog.mo -g prog.elf
```

不开 `-g` 时输出字节**完全不变**（自举要求），不会多出任何调试节。

## 能提供什么

| 能力 | 状态 |
|---|---|
| 按源码行下断点、看行号 | ✅ 1.16 起 |
| **看局部变量** | ✅ 1.50 起（`DW_AT_location`） |
| **看全局变量** | ✅ 1.50 起（`DW_OP_addr`） |
| **看调用栈回溯（bt）** | ✅ 1.51 起（`.debug_frame`） |
| **打印结构体成员** | ✅ 1.52 起（`DW_TAG_structure_type` + member） |
| **变量显示正确类型**（f64/bool/ptr/数组） | ✅ 1.52 起 |

## 类型 DIE

```
DW_TAG_compile_unit
├── DW_TAG_base_type       i64 / byte / f64 / bool
├── DW_TAG_pointer_type    （ptr，带目标类型）
├── DW_TAG_structure_type  Point
│   ├── DW_TAG_member x @ 0
│   └── DW_TAG_member y @ 8
├── DW_TAG_array_type
│   └── DW_TAG_subrange_type  count = N
└── DW_TAG_subprogram ...
```

类型 DIE 必须在引用它的变量 DIE **之前**生成，所以走两遍：
`dbg_ty_prepass()` 先把所有变量用到的类型都生成好，
之后变量 DIE 只用 `ref4` 指过去。同一类型只生成一份（表 `O_DTY`）。

自引用类型（`struct Node { next: ptr }`）靠**先登记偏移再写子 DIE**
来避免无限递归。

## 🔴 三个"看起来对其实错"的常量

| 写错的 | 实际 | 后果 |
|---|---|---|
| `t >= 100` 判断"是不是类型对象" | `ty_new` 的 id 从 **2** 开始 | f64/bool/ptr 全被当成裸 id → 所有这类变量的 `DW_AT_type` 指向同一个类型 |
| `DW_TAG_subrange_type` = 21 | **33** (0x21) | 21 是 `subroutine_type`，数组子范围被解成函数类型 |
| `DW_AT_count` = 53 | **55** (0x37) | 53 是 `DW_AT_base_types`，数组长度显示成奇怪的属性 |

三者共同点：**readelf 都能打出东西**，只是内容全错。
所以类型相关的断言必须逐个比对名字（"fl 是 f64"），
不能只检查"每个变量都有类型"。

## .debug_frame（栈帧展开）

有了它 gdb 才能 `bt`。墨语言的序言固定为
`push rbp`(1) + `mov rbp,rsp`(3) + `sub rsp,imm32`(7)，
所以 CFA 只有三种取值：

| 位置 | CFA |
|---|---|
| 入口 | `rsp + 8` |
| `push rbp` 之后 | `rsp + 16` |
| `mov rbp,rsp` 之后 | `rbp + 16` |

每个函数一条 FDE，指令序列只有 4 条：
`advance 1` → `def_cfa_offset 16` → `offset rbp @ cfa-16` →
`advance 3` → `def_cfa_register rbp`。

**已知限制**：函数中间的 `return` 会各自生成尾声，CFI 不描述它们
（只保证到函数末尾）。在 `ret` 上停住时回溯可能不准，
函数体内任意位置均正确。

## DIE 结构

```
DW_TAG_compile_unit
├── DW_TAG_base_type  "i64"        （变量的 DW_AT_type 指向它）
├── DW_TAG_variable   TOTAL        （全局，location = DW_OP_addr）
└── DW_TAG_subprogram main
    ├── DW_TAG_variable i          （fbreg -8）
    └── DW_TAG_variable s          （fbreg -16）
```

### 为什么 frame_base 用 `DW_OP_breg6 + 0`

`DW_AT_frame_base = DW_OP_breg6(rbp) + 0`，于是变量的 `fbreg` 偏移
**就是反汇编里看到的 `[rbp+off]`**，不需要换算 CFA。

代价：gdb 打印 `bt` 需要 `.debug_frame` 里的 CFA 规则，这一项还没做。
换来的是看变量这件事**立刻可用且不依赖栈帧展开**。

## 🔴 局部变量不能从符号表推导

`parse_func` 结束时有 `sv(K_NSYM, ra)` 把符号表**回滚**到进入时的位置，
局部变量符号全部丢弃。所以必须在 `parse_let` 里另记一份
（`O_DV` 表：名字 / rbp 偏移 / 声明行 / 所属函数下标）。

函数边界同理记在 `O_DF` 表（名 / low_pc / high_pc / 声明行）。

两张表都在 `DBG` 缓冲区（已从 4MB 扩到 8MB），只在 `-g` 时写入。

## 🔴 db_sleb 的既有 bug：负数编码一直是错的

```mo
v = v / 128;      # 墨语言的 / 对负数**向零截断**
```

SLEB128 要求**算术右移**（向下取整）：`-8 >> 7 = -1`，而 `-8 / 128 = 0`。
于是 `v == -1` 那个终止分支永远进不去，负数被多编一个字节：

```
-8  编成 f8 00   → 解出来是 +120
-16 编成 f0 00   → 解出来是 +112
```

**行号表没暴露它**，因为行号增量基本都是正的（单调递增）。
一用来编码变量相对 rbp 的**负**偏移，gdb 读到的位置就全是正数、完全错乱。

修法是补上向下取整：

```mo
let q: i64 = v / 128;
if v < 0 { if q * 128 != v { q = q - 1; } }
v = q;
```

`db_sleb_len`（算 exprloc 长度）必须用**同样**的除法，否则长度字段
和实际字节数不一致，表达式会被读错位。

## 验证：`tools/dwvar.py`（40 项）

本机没有 gdb，所以不能只靠"readelf 打得出来就算对"。
`dwvar.py` 做一件更硬的事：

1. 从 `.debug_info` 读出每个局部变量的 `fbreg` 偏移
2. **反汇编该函数的机器码**，收集所有 `[rbp+off]` 访问
3. 断言：DWARF 里记的每个偏移，都能在该函数的机器码里找到

这能抓住"偏移算错 / 变量归错函数 / sleb 编码错"——
它们都会让 gdb 读出垃圾值，而 readelf 看起来一切正常。

```
✓ addup: DWARF 偏移 [-24] 都能在机器码里找到
✓ main:  DWARF 偏移 [-8, -16] 都能在机器码里找到
```

另外校验：

- 全局变量地址落在数据段（≥ 0x10000000）、声明行号、
  "先声明的变量偏移更接近 0"
- **FDE 与真实序言吻合**：每个 FDE 的 `low+0` 处必须真的是 `push rbp`(0x55)，
  `low+1..4` 必须是 `mov rbp,rsp`(48 89 e5)。CFI 说"advance 1 后 CFA=rsp+16"，
  那第 1 字节处就必须是那条 push —— 这条断言把 CFI 和机器码钉在一起。

## 🔴 两个写盘层面的坑

1. **写盘顺序必须与 `gen_shdr` 里累加 `o` 的顺序一致**。
   第一版按旧顺序把 `.shstrtab` 写在 `.debug_frame` 之前，
   于是节头表里两者的 offset 互换，readelf 打出的节名全是乱码、
   报 "Corrupt debuglink" —— 而**程序照常运行**，只有调试信息废了。
2. **`DW_CFA_def_cfa_offset` 是 0x0e，不是 0x0f**。
   0x0f 是 `DW_CFA_def_cfa_expression`，要跟一个 DWARF 表达式块，
   于是把后续字节当成长度解析，readelf 报 "corrupt len"，CFA 规则全废。

## 已知限制

- 函数参数不生成 `DW_TAG_formal_parameter`
- enum 类型不生成 DIE（按 i64 显示）
- 中间 `return` 的尾声处 CFI 未描述（见上）
- 变量表上限 60000 条、函数表 4000 条，超出后静默丢弃
