# 系统级能力：内核、Windows、安卓、服务器包、内核模块、包管理

版本 1.17.0（2026-10-09）

一句话：**墨语言现在既能写应用，也能写系统。**

| 目标 | 命令 | 产物 |
|---|---|---|
| **Linux 内核镜像** | `bash tools/kernel.sh examples/kernel.mo k.elf` | Multiboot ELF（GRUB/QEMU 可加载） |
| **Windows 原生** | `bash tools/winbuild.sh app.mo app.exe` | PE32+ 控制台/GUI 程序 |
| **安卓原生** | `bash tools/android_native.sh app.mo app` | 静态 ARM64 ELF（**无需 NDK**） |
| **服务器包** | `bash tools/pkgserver.sh app.mo svc` | systemd + deb + rpm + Docker |
| **Linux 内核模块** | `bash tools/kmod.sh mod.mo name` | 可 `make` 成 `.ko` 的 C + Makefile |
| **包管理** | `bash tools/mopkg.sh install <git-url>` | `deps/` + `mo.lock` |

全部由 `bash tools/targets_test.sh` 自动验证（19 项）。

## 运行时验证

**内核与 UEFI 都已在 CPU 模拟器里真正执行**，详见
`docs/runtime_verification.md`：

```bash
bash tools/kernrun_test.sh     # 内核：启动、键盘输入、算术
bash tools/uefirun_test.sh     # UEFI：固件环境、fib、整数计算
```

## 内核

32 位 Multiboot1，`boot/entry32.S` 提供入口（清 bss、建栈），
`boot/linker.ld` 把 `.multiboot` 放在最前面。

**和 cfs 后端的根本区别**：内核不能做系统调用（它自己就是提供系统调用的
那一层），所以输出走 VGA 缓冲 `0xB8000`，I/O 走 `in/out` 端口。

于是**同一份墨语言源码**里的 `print_i64()`：
- 编成用户态 → `write(1, ...)`
- 编成内核 → 直接往 `0xB8000` 写字符

`examples/kernel.mo` 是一个真内核：ring0、轮询键盘、带一个最小 shell
（help / echo / add / ticks / clear / halt）。

### 踩到的坑

`.section .multiboot` 不加 `"a"`（allocatable）标志，lld 就不会把它放进
可加载段 —— 于是 Multiboot 头跑到文件偏移 12920，超出规范要求的 8192 字节。
症状是"链接成功但 GRUB 认不出来"，非常迷惑。

## Windows

`zig cc -target x86_64-windows-gnu`，无需 MSVC/MinGW（zig 自带 mingw libc）。
生成 C 前置 `print` 家族的 `printf` 实现（必须在**使用之前**声明）。

## 安卓原生（不用 NDK）

原理：**Android 的内核就是 Linux 内核**，ARM64 系统调用号一致。
所以 `cfs-aarch64` 后端产出的静态、无 libc 的 ARM64 ELF，
`adb push` 上去就能跑。

与 NDK/JNI 路径的定位区别：
- 这条路径做**命令行原生程序**（Termux、root shell、init 脚本）
- NDK 路径做**带界面的 App**（JNI `.so` + APK）

`-nostdlib` 是必需的：后端自带 `_start`，会与 musl 的 crt 冲突。

## 服务器交付

`pkgserver` 不只要"能跑"，还要能被交付：

- systemd unit（带 `ProtectSystem=strict` 等最小权限）
- `DEBIAN/control` → `dpkg-deb --build` 即可
- `.spec` → `rpmbuild` 即可
- `Dockerfile` → **`FROM scratch`**（静态 ELF 不需要任何基础镜像）

## 运行时验证

**内核与 UEFI 都已在 CPU 模拟器里真正执行**，详见
`docs/runtime_verification.md`：

```bash
bash tools/kernrun_test.sh     # 内核：启动、键盘输入、算术
bash tools/uefirun_test.sh     # UEFI：固件环境、fib、整数计算
```

## 内核模块

mo2x 产出 C，套 `module_init`/`module_exit`，`print` 映射到 `printk`。
**没有内核头文件时明确报错**并说明装什么（退出码 3），不假装成功。

## 包管理

依赖就是 git 仓库，不做中心仓库（中心仓库要维护服务端，而 git 引用
已经解决分发问题）。`mo.lock` 记录 commit 保证可复现。

## 仍然没做到的（诚实列出）

- ~~内核没在真机/QEMU 上跑过~~ **已在 CPU 模拟器里真跑通**（1.20.0）：本机装不上 qemu，只验证到
  "Multiboot 头位置正确 + 无 libc + 入口正确"。**没有运行时验证**。
- **`.ko` 没编译过**：本机没有内核头文件。只验证到"C 与 Makefile 正确生成"。
- **APK 没构建**：本机没有 Android SDK。
- **GUI**：Windows GUI 子系统只生成了 PE 框架，没有 Win32 窗口代码。
- 内核是 32 位的（Multiboot1）；**UEFI 64 位应用已支持**，见 `docs/uefi_kernel.md`
- UEFI 应用没有在真机/QEMU 上跑过（本机没有 OVMF），只验证到产物结构。
