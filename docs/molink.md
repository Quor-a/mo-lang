# molink —— 墨语言自己写的静态链接器

```
./bin/moc tools/molink.mo -nostdlib bin/molink
./bin/moc prog.mo -nostdlib -c prog.o
./bin/molink prog.o -o prog
./prog
```

## 它解决什么

在此之前，「链接」这一步必须借 GNU ld 的手：

```bash
ld --section-start=.data=0x10000000 -e _start -o prog prog.o mocrt.o
```

而 `-nostdlib` 时还要**先用 `as` 汇编 `tools/mocrt.s`** 补一个 `exit`。

也就是说：**编译器是自举的，链接器和运行时却不是**。自包含生态在这
最后一环上是断的。

`tools/molink.mo` 把这条路径完全自己做掉，全程**不调 ld、不调 as**。

## 段布局

```
第 1 页  0x400000   ELF 头 + 程序头        R
第 2 页  0x401000   .text (+ exit stub)   R X
第 N 页  0x10000000 .data                 R W
```

两个地址是硬的：

- **`.data` 必须是 `0x10000000`** —— 编译器给全局变量发的是
  `movabs rax, 0x10000000+off` 绝对地址。搬错地方**不报错**，
  只是所有全局变量读成垃圾。
- **`.text` 必须避开第 1 页** —— 见下面第一个坑。

`.data` 的文件偏移按 `.text` 的实际大小计算（`alignup(4096+tsz, 4096)`），
不能写死。

## exit stub：连 mocrt.s 都不需要

`-nostdlib` 编译时，编译器收尾用的是 `exit`，而它在 `.o` 里是 UND。
molink 直接注入 9 字节：

```
48 c7 c0 3c 00 00 00     mov $60, %rax      # exit_group
0f 05                    syscall
```

放在 `.text` 末尾，符号值指向它。`R_X86_64_PLT32` 对本地定义的符号
按 PC32 处理（`S + A - P`）即可。

## 三个真坑

### 1. `.text` 不能和 ELF 头同页

第一版把 `.text` 放 `0x400000`、文件偏移 0，于是 `_start` 的地址正好
落在 **ELF magic 上** —— 一执行 `7f 45 4c 46` 就段错误。

症状很怪：链接"成功"、文件大小正常、`readelf` 也读得出程序头，
只有一跑就 `SIGSEGV`。

修法是照 ld 的布局：第 1 页放头（只读、不可执行），text 从第 2 页起。

### 2. `.data` 偏移写死 → 大例子 SIGBUS

第一版 `doff` 写死 8192。小例子 text 只有 98 字节，恰好通过；
`plot.mo` 的 text 有 14830 字节，于是

```
p_offset=4096  p_filesz=14839   → 需要文件 ≥ 18935 字节
实际文件 = 8192 + 480            → 8672 字节
```

文件比程序头声明的短，内核 mmap 越界 → **`SIGBUS`（不是 SIGSEGV）**。

> 小样本通过、大样本崩，是这个 bug 的典型形态。
> 只拿 98 字节的例子测链接器，永远发现不了。

### 3. 全局数据接近 1MB 时编译器静默损坏符号表

两个 `[524288] byte` 数组 + 一个 `[64] i64` 数组：

```
molink.mo:68:38: error: undefined symbol 'OBJF'
```

而 `var OBJF: [524288] byte = 0;` 就在上面 30 行。单独用、两个数组用
都正常，加上第三个就报**别处**未定义 —— 符号表被静默破坏了。

改成用堆分配（`alloc`）后正常。**写工具时遇到"明明声明了却说未定义"，
先数一下全局数据总量。**

## 验证：不是"能跑就行"

`tools/molinktest.sh` 对同一批 `.o` 分别用

- `bin/molink`（墨语言，不调 ld）
- `tools/molink.sh`（GNU ld + mocrt.s）

链接并运行，**逐字节比对 stdout 与退出码**：

```
✓ bubble_sort  calc  sort  freq  grep  plot  bignum  mclass
✓ 变异验证：把 .data 基址改错 → 原版 0 / 变异版 139
```

第二项才是关键：如果改错地址后结果还一样，那第一项的"输出一致"
就什么都没检验。**链接错误最常见的表现是"程序照常跑、值却是错的"**，
所以必须有一个能证伪的对照。

## 支持与不支持

支持：`R_X86_64_64` / `PC32` / `PLT32` / `32S`；多个 `.rela.*` 段。

不支持（**明确报错**，不静默产出坏文件）：

- 依赖 libc 的动态链接 —— 需要 `.interp` / `.dynamic` / `.plt`，
  那条路请用 `tools/molink.sh`
- UND 的外部符号（`extern` 声明的 C 函数）
- 其它重定位类型
