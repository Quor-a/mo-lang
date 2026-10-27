# 安卓 rootfs：把"跑不起来"的三类静默失效摆到明面上

## 背景

在 arm64 设备上跑墨语言工具链（工具链本身是 x86_64 ELF），
需要一个 proot rootfs + 用户态翻译器。真机实测（2026-10-24，
设备 arm64-v8a，无 Root）暴露了四类失效，**每一类的报错都不指向真因**。

## 四类失效与其真因

| 症状 | 真因 |
|---|---|
| `execve("/box64"): No such file or directory` | box64 是 aarch64 **动态链接 PIE**，rootfs 里既没有它的 loader 也没有 `lib/`。文件明明在，报的却是"不存在" |
| `can't chdir to '/work'` | proot 的工作目录根本没人建 |
| `Permission denied` / `Function not implemented` | rootfs 顶层是 `700`，proot 的 tracee 以 app uid 运行时进不去 |
| `undefined symbol: MO_ARGC` | LTO 把只被 `_start` 的 naked asm 引用的变量删掉了 |

前三类属于**打包**，第四类属于**构建参数**。都已在正确位置修掉。

## 修在哪

- `tools/mkrootfs.sh` —— 生成 rootfs。显式建 `work/`、显式 `chmod 755`、
  并对翻译器做**自包含校验**：动态链接就用 `ldd` 解析依赖并全部复制进去，
  解析不出来就报错退出，不做"大概能跑"的猜测。
- `tools/rootfscheck.sh` —— 六层判据校验任意 rootfs。
- `tools/rootfsxlate.py` —— 翻译器自包含判定（静态 / 缺 loader / 缺库）。
- `tools/android_native.sh` —— 加 `-fno-lto`。

## 为什么 -fno-lto 是必需的

`MO_ARGC` / `MO_ARGV` 只被 `_start` 的 **naked 内联汇编**引用，
C 代码里没有任何一处读它们。LTO 做全局可达性分析时看不见 asm 里的引用，
判定"只写不读"，把变量整段删掉 —— 链接期报
`undefined symbol: MO_ARGC`，而源码、mo2x 产物、汇编里都明明白白写着它。

不加 `-fno-lto` 必现；加了即过。同理这两个变量必须**非 static**
（static 在 -O2 下同样会被删）。

## mo2x footer 的死分支（已清理）

`tools/mo2x.mo` 里曾有**两个** `if TGT == T_FS` 完整块。第一个命中后
`return 0`，第二个永不可达 —— 而它里面 `mo_syscall(MO_EXIT_, r, ...)`
的 `r` **根本没有定义**（缺 `long r = mo_main();`），且只处理 aarch64
与 x86_64，ppc64 / s390x / RISC-V 会掉进 x86_64 的 `movq` 分支。

死代码不执行，所以不报错；但它会让读代码的人以为"有另一条路径"。

## 判据

`tools/rootfstest.sh` 7 项：新打包的 rootfs 六层全过，
外加四类真机破坏（删 `work/`、顶层改 700、删 `moc`、翻译器不带 loader）
**必须**被检查器抓到 —— 只测"好 rootfs 能过"证明不了检查器有效。

## 已知限制

- 沙盒宿主是 x86_64，**翻译器路径（[4]）未被端到端执行**，只有判据逻辑：
  测试里用 `/bin/ls` 当动态链接翻译器验证"缺 loader 必被抓"。
- rootfs 不含 zig，交叉编译需在宿主侧做完后把产物放进去。
- proot 本身在 app 沙箱下的 SELinux 限制（ENOSYS）无法从 rootfs 侧解决。
