# 包管理器：在安卓上跑，自带运行与执行环境

`examples/pkgmgr.mo` —— 一个**在安卓原生（ARM64）上可执行的包管理器**，
且它自己就是运行环境：包里带字节码，包管理器自带栈式 VM 执行它。

```bash
bash tools/android_native.sh examples/pkgmgr.mo /tmp/pkgmgr
adb push /tmp/pkgmgr /data/local/tmp/pkgmgr
adb shell /data/local/tmp/pkgmgr
```

它对应四个要求：

| 要求 | 怎么满足 |
|---|---|
| 包管理能在安卓上跑 | 纯 syscall，不 fork / 不 exec / 不链 libc |
| 可以开发升级包管理 | 包 = 目录 + 清单；install / remove 即升级 |
| 可以运行执行开发的包 | 包里存字节码，自带栈式 VM 真正执行 |
| 自带运行和执行环境 | 静态 ELF，产物不依赖任何外部运行时 |

## 为什么"执行包"不靠 fork + execve

现有 `lib/mopkg.mo` 走 `fork + execve + pipe + dup2 + wait4`，还依赖 git。
**ARM64 根本没有 fork**（只有 `clone(220)`，参数形态完全不同），execve 又要加载器。
照搬 mopkg 上安卓，第一步就走不通（v1.154 已诊断）。

所以"执行"改成：**包里存字节码，包管理器自带 VM 解释它**。
同一份包在手机和 x86 上跑出同样的数字，不需要任何外部进程。

## 布局与格式

```
/tmp/mo_pkgs/
  demo/  MANIFEST   name=demo\nversion=1.0.0\n
         CODE       栈式字节码
  demo2/ ...
```

VM 指令（1 字节 opcode）：

```
0 HALT    1 PUSHI imm32(小端)    2 ADD    3 PRINT    4 MUL
```

演示包：

| 包 | 字节码 | 输出 |
|---|---|---|
| demo | `6 * 7` | **42** |
| demo2 | `2 * 42` | **84** |

两个数字刻意不同 —— 否则分不清"VM 真执行了"和"碰巧打印了一个常量"。

## 实测（两端）

`make pkgmgrtest`，18 项断言，**ARM64 模拟器与 x86-64 真机各跑一遍**：

```
[1] init root     ret=0
[2] install demo  code=13
[3] install demo2 code=13
[4] list count    =2        demo demo2
[5] info demo     ver=1.0.0
[6] run demo      out=42
[6] run demo2     out=84
[7] remove demo   ret=0
[8] list after rm =1        demo2
pkg ok = 1
```

## 🔴 修掉的真缺陷

### 一、getdents64 的号表写错，且**只在 ARM64 端暴露**

```mo
if n == 217 { return 217; }   # 此前
```

217 是 **x86-64** 的 getdents64。ARM64 走 asm-generic 表，`getdents64 = 61`，
而 ARM64 的 **217 是 `add_key`**（keyring）。

后果是本项目最警惕的那种：不报错、不崩溃，只是列目录发成了"往内核密钥环里加密钥"，
于是 `list` 在手机上永远得到空列表 —— **只跑 x86 的测试永远发现不了**。

修：`217 → 61`，并新增 `tools/sysnocheck.sh`，把整张表与
`/usr/include/asm-generic/unistd.h` **逐条自动比对**（16 项），
头文件缺失时明确报错而不是静默跳过。

### 二、手写循环被 C 编译器换成库函数调用（v1.154 那个坑的根因）

freestanding 产物不链 libc，但 clang 会在 IR 层把手写循环识别成库函数调用：

| 源码里写的 | 编译器换成的 | 链接时 |
|---|---|---|
| `while (s[i]) i++;` | `strlen(s)` | undefined symbol: **strlen** |
| 大数组 `= 0` | `memset(...)` | undefined symbol: **memset** |

关键：**`#define strlen strlen_` 这种别名宏挡不住** —— 宏是预处理阶段的事，
而编译器插入对**原名 `strlen`** 的引用发生在那之后。

v1.154 当时的绕法是"数组不写 `= 0`"，治的是症状。这里修根因：
`fs_header()` 直接提供 `strlen` / `memset` / `memcpy` **原名符号**，
并且 `android_native.sh` 加 `-fno-builtin`（双保险）。

### 三、cfs 后端没有内存原语宏

`load8` / `store8` 的宏此前**只有 kern 后端**输出，cfs 不输出，
于是 freestanding 程序里写 `load8` 得到 `call to undeclared function 'load8'`。
这让 cfs 上读不了目录项（getdents64 的 buffer 必须逐字节解），也解析不了清单。
现在 `fs_header()` 与 kern 共用同一份 `emit_mem_macros()`。

### 四、rmdir：x86 有，asm-generic 没有

x86-64 有独立的 `rmdir(84)`；asm-generic **没有**，新架构只有
`unlinkat + AT_REMOVEDIR`。解法是让 `AT_REMOVEDIR(512)` **由源码写在第二实参**：

```mo
syscall(84, &PATH, 512, 0, 0, 0);
```

- x86（透传）→ `rmdir(path)`，第二实参被忽略 ✓
- ARM64（换号 84→35 + 插 dfd）→ `unlinkat(-100, path, 512)` ✓

两端同一语义，源码不需要知道目标架构。

## 变异验证（`make pkgmgrmut`，5 / 5 被捕获）

| 变异 | 结果 |
|---|---|
| M1 getdents64 退回 217 | 4 项红 |
| M2 cfs 不输出内存原语宏 | 2 项红（构建失败） |
| M3 去掉 rmdir 号表项 | 2 项红（构建失败） |
| M4 VM 的 MUL 退化成 ADD | 7 项红（42/84 → 13/44） |
| M5 忘记跳过 `.` 与 `..` | 9 项红 |

M5 顺带暴露了模拟器与真机的不一致：模拟器原先的 `getdents64` 不返回
`.` 和 `..`，于是这类错误在模拟器里永远抓不到。现在补上了。

## 已知限制

- 路径写死 `/tmp/mo_pkgs`，无依赖解析、无版本约束、无校验和
- 清单只解析 `version=`，不是完整 TOML
- VM 只有 5 条指令，无跳转、无调用、无字符串
- 一个包只有一个 CODE；无"包内多文件"
- 模拟器是内存文件系统，与真机的错误码细节可能有差异

## 下一步

最有杠杆的是 **给包加校验和**（需要哈希库，已有 `lib/lsh.mo` 的 splitmix64 可用），
以及 **清单解析成完整键值表**（现在只取 version）。
