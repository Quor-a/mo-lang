# UEFI 应用（64 位固件环境）

版本 1.19.0

```bash
bash tools/uefi.sh examples/uefi.mo /tmp/mouefi.efi
```

产物：`PE32+ / x86-64 / 子系统 10 (EFI application)`，4096 字节。

## 它和 32 位内核（kernel.mo）的区别

| | 32 位内核 | UEFI 应用 |
|---|---|---|
| 环境 | 裸机 ring0，自己接管硬件 | 固件环境，跟固件合作 |
| 输出 | 直接写 VGA `0xB8000` | `ConOut->OutputString` |
| I/O | `in`/`out` 端口 | UEFI 协议 |
| 引导 | Multiboot1（GRUB） | UEFI 固件加载 PE |

所以同一个 `print_i64()`，三种后端三种实现：

- 原生/cfs → `write(1, ...)` 系统调用
- kern → 写 `0xB8000`
- **uefi → `ConOut->OutputString`**

## 关键布局（x86-64）

```
EFI_SYSTEM_TABLE:
  +64   ConOut   (EFI_SIMPLE_TEXT_OUTPUT_PROTOCOL*)

EFI_SIMPLE_TEXT_OUTPUT_PROTOCOL:
  +8    OutputString   EFI_STATUS (*)(This, CHAR16*)
  +48   ClearScreen    EFI_STATUS (*)(This)
```

`CHAR16` 是 **UTF-16LE**，所以 ASCII 要拆成"低字节, 0"两字节再传。

调用约定是 **Microsoft x64**（rcx/rdx/r8/r9）——而本目标按
`x86_64-windows-gnu` 编译，编译器自动用 MS ABI，
所以直接当普通函数指针调用即可，不需要手写汇编。

## 踩到的两个坑

**1. zig 0.17 的 `x86_64-uefi` 目标取不到 libc**

```
error: unable to provide libc for target "x86_64-uefi...msvc"
```

它要求 MSVC ABI 的 libc。而 UEFI 应用本质上就是 subsystem=10 的 PE32+，
所以按 Windows 目标编、但用 `efi_application` 子系统是等价的，绕开了这个限制。

**2. 入口名是 `EfiMain`，不是 `efi_main`**

lld-link 在 `--subsystem,efi_application` 下默认找的入口符号叫 **`EfiMain`**。
用 `efi_main` 会报 `undefined symbol: EfiMain`——注意它报的是"找不到 EfiMain"，
而不是"你写的 efi_main 没人调用"，很容易误导。

另外 UEFI 不能用 mingw 的 crt（它会去找 `WinMain`/`main`），必须 `-nostdlib`。

## 没做到的

- **没有在真机或 QEMU 上跑过**：本机没有 OVMF（UEFI 固件），
  只验证到产物结构（PE32+ / x86-64 / 子系统 10 / 入口正确）
- **图形输出（GOP）没做**：`ConOut` 只是文本输出。
  GOP 要读 `BootServices->LocateProtocol` 与 `Mode->Info`，更复杂
- 键盘输入（ConIn）没做
