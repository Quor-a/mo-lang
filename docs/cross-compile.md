# 交叉编译（Mo 程序 → 任意平台）

Mo 程序有两种编译路径：

| 路径 | 产物 | 平台 |
|------|------|------|
| 原生 `moc`（自举编译器） | 静态 ELF | x86-64 Linux |
| **C 后端 `mo2x` + zig** | 任意目标 | x86-64/ARM64 Linux、macOS（Intel/Apple Silicon）、Windows x64、WASM |

## 用户程序交叉编译

```bash
# 1. Mo → C
./bin/mo2x prog.mo c > prog.c

# 2. C → 任意目标（zig 提供交叉编译与各平台 libc）
zig cc -target aarch64-linux-musl  -O2 prog.c -o prog-arm64-linux
zig cc -target aarch64-macos       -O2 prog.c -o prog-macos
zig cc -target x86_64-windows-gnu  -O2 prog.c -o prog.exe
zig cc -target x86_64-linux-musl   -O2 prog.c -o prog-x86-linux
zig cc -target wasm32-wasi         -O2 prog.c -o prog.wasm   # 见 tools/wasm.sh
```

zig 缺失时 `pip install ziglang` 后用 `python3 -m ziglang cc` 等价
（`tools/zigcc.sh` 自动处理）。

## 注意事项

- **库的 syscall 号表**：`mo2x c` 目标对 `lib/` 里直接用 syscall 号的
  代码（如 `mem.mo`）会报"该目标架构暂无 syscall 号表"。程序自绘
  `print`（像 `examples/wasmdemo.mo` 那样用 `syscall(1,1,...)`）即可，
  C 后端会在非 Linux 目标自动替换为 printf 实现。
- **freestanding (`cfs-*`) 后端**没有 `load8`/`store8`；`syscall()` 在
  aarch64 会自动把 open/mkdir/stat 等适配成 `*at` 版本（首参自动插入
  `AT_FDCWD`），源码里要少写一个占位实参。
- **32 位移位坑**：生成的 C 里移位量 ≥32 必须由 i64 变量承载，
  字面量/字节提升的 `<<32` 是未定义行为（LLVM 折成 0，静默数值错误）。
  详见仓库根 CLAUDE.md「mo2x 的 32 位移位」一节。

## Release 里的演示产物

每个 Release 附带 `demo/fib-*`（自包含 Fibonacci 程序）：
aarch64-linux（qemu 实测运行正确）、aarch64-macos、x86_64-windows.exe、
x86_64-linux。构建脚本 `release/build-release.sh` 可复现。

## 编译器自身（moc）的平台边界

`moc` 是自举编译器（用 Mo 写成），当前只在 x86-64 Linux 上运行；
其源码依赖原生后端的 syscall 号表，`mo2x` 尚不能把它转译到 C
（`mo2x src/compiler.mo c` 报 syscall 表缺失 —— 这是已知的自举
边界，见 docs/community_findings.md）。在其它平台运行编译器目前需要
x86-64 Linux 机器（或 qemu-user）跑 `moc`，再用 `mo2x`+zig 产出目标平台
的**用户程序**。
