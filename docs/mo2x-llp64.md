# mo2x C 后端：LLP64 修复（v1.1161）

## 症状

Windows 上交叉编译出的 `fib-x86_64-windows.exe` 跑不起来。

## 根因：`long` 在 Windows 上是 32 位

mo2x 的 C 前导（`emit_mem_macros` + C 目标 prelude）一直用 `long` 表示 Mo 的 `i64`：

```c
#define load64(p)  (*(long*)(p))
#define store64(p,v) (*(long*)(p) = (long)(v))
static long call1(long f, long a){ long (*g)(long)=(long(*)(long))f; return g(a); }
static long print_i64_(long v){ return (long)fprintf(stdout, "%ld", v); }
```

在 Linux / macOS（LP64）`long` 是 64 位，看起来毫无问题。
**Windows x86_64 是 LLP64 —— `long` 只有 32 位**，于是：

| 原语 | Windows 上的实际行为 |
|---|---|
| `load64` | 只读 4 字节并符号扩展 → 数组/结构体读错值 |
| `store64` | 只写 4 字节，高 4 字节是垃圾 → 内存被踩坏 |
| `call0..3` | 64 位函数指针被截成 32 位 → 调用跳飞 |
| `print_i64_` + `%ld` | 大数截断 |
| `atomic_cas` | 指针截断 |

Mo 的函数签名本身发的是 `long long`（所以简单算术看着正常），但所有**经由前导原语**的
路径 —— 数组、指针、闭包调用、打印大数 —— 在 Windows 上全是错的。
小 demo 只走标量算术，可能侥幸跑起来；一旦用数组或函数指针就崩。

## 修法

前导里凡是承载 Mo `i64` 的地方一律改 `long long`（LP64 下 `long long` 同样是 64 位，
不会破坏 Linux/macOS/aarch64）：

- `emit_mem_macros()`：`load64` / `store64` / `atomic_cas` / `call0..3`；
- C 目标 prelude：`mo_syscall`、`strlen_`、`print_` / `print_i64_` / `print_nl_` / `print_hex_`，
  格式化串跟着改 `%lld` / `%llx`；
- f-string 拼接游标 `MF_P=(long)` → `MF_P=(long long)`（指针截断）。

freestanding / ARM / RISC-V / UEFI 后端的 `register long r0 asm("rax")` 一类**不动**：
那些 ABI 是 LP64，`long` 就是 64 位，且寄存器约束必须用与寄存器同宽的类型。

## 验证

- 生成物里不再出现裸 `long`：

```
$ /tmp/mo2x tools/…/demo.mo c | grep -E "\blong\b" | grep -v "long long"
（空）
```

- 四平台重编，Linux 与 aarch64(qemu) 输出逐字节一致；
- Windows 产物结构核对：PE32+ console x86-64、子系统 6.0；
  另出一个**只依赖 KERNEL32** 的版本（`-nostdlib` + 自带 `mainCRTStartup`，
  打印走 `WriteFile`），彻底去掉 UCRT 依赖，4 KB。

## 已知限制

本机没有 Windows / wine，**无法实际执行** exe。上面的验证是结构级与生成物级的
（PE 头、导入表、子系统版本、未执行）。运行时验证需要用户在 Windows 上确认。

## 顺带的教训

- 跨平台后端里**不要用 `long` 承载固定宽度整数**，哪怕目标全部是 64 位系统 ——
  LLP64 是唯一但致命的例外。
- 「交叉编译成功」不等于「目标平台能跑」：这次四个平台都编译通过、Linux 全绿，
  唯独 Windows 因为 `long` 宽度不同而带着一整套错误语义。
