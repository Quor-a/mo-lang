# pkgarm.mo —— **包管理在安卓上运行**的最小地基（freestanding，不链 libc）
#
# mo-target: cfs-aarch64   # 非原生后端，projcheck 跳过原生编译
#
#   bash tools/android_native.sh examples/pkgarm.mo /tmp/pkgarm
#   adb push /tmp/pkgarm /data/local/tmp/ && adb shell /data/local/tmp/pkgarm
#
# 为什么这个例子不可省
# --------------------
# 现有 lib/mopkg.mo 走的是「fork + execve + pipe + wait4 执行外部命令」模型
# （sh_capture），并且依赖 git 做 clone / rev-parse：
#
#   sh_fork    syscall(57)   ← ARM64 没有 fork，只有 clone(220)，参数形态完全不同
#   sh_pipe    syscall(22)
#   sh_dup2    syscall(33)
#   sh_execvp  syscall(59)
#   sh_wait    syscall(61)
#   sh_chdir   syscall(80)
#   sh_getcwd  syscall(79)
#
# 其中 22/33/57/79/80 在 mo2x 的 x86→asm-generic 翻译表里**查不到**，
# 于是任何 import sh.mo 的程序编到 cfs-aarch64 会直接失败退出（响亮报错，
# 不是静默发错号）。也就是说：**照搬 mopkg 上安卓，第一步就走不通**。
#
# 本例证明另一条路是可行的：包管理真正需要的动作只有五个——
#
#   建目录 mkdirat · 写文件 openat+write · 读文件 openat+read
#   查询   newfstatat · 删除 unlinkat
#
# 这五个在 v1.153 已做 *at 实参重排，是**纯 syscall、不需要 fork/exec/git**。
# 所以包管理完全可以做成自包含的：不 fork 子进程、不调 git、不链 libc。
#
# 判据不靠自证：读回的内容**再写到 stdout**，由测试脚本 grep ——
# 程序自己写错了会一起错，比在程序里比对自己写的值更可信。

fn main() -> i64 {
    # 包目录与包内清单文件
    let dirp: ptr = "/tmp/mo_pkg_demo";
    let filep: ptr = "/tmp/mo_pkg_demo/MANIFEST";
    let want: ptr = "MO-PKG-OK\n";
    let fd: i64 = 0;
    let n: i64 = 0;
    let ok: i64 = 1;
    let buf: [32] i64 = 0;
    # sbuf **故意不写 = 0**：freestanding（无 libc）下，64 个 i64 的零初始化
    # 会被 C 编译器优化成对 memset 的调用，链接时报
    #   ld.lld: error: undefined symbol: memset
    # 而 32 个 i64（buf）不会 —— 于是"多加一个数组"就让整个产物链接失败，
    # 症状完全不指向数组。这是"自带运行环境"最容易踩的一类坑。
    let sbuf: [64] i64;

    # 1) 建包目录 —— 包管理器的 install 第一步
    # 🔴 mode 必须是 493(0755) 而不是 420(0644)：目录需要 x 位才能进入，
    #    0644 的目录建出来是 drw-------，随后 open(dir/file) 一律 EACCES(-13)。
    #    症状是 "mkdir ret = 0 成功、open W fd = -13"，极具迷惑性。
    #    （ARM64 的 mkdirat 语义相同，两端一致。）
    n = syscall(83, dirp, 493, 0, 0, 0);
    print("mkdir ret   = ");
    print_i64(n);
    print_nl();

    # 2) 写清单 —— O_WRONLY|O_CREAT|O_TRUNC = 577，mode 0644 = 420
    fd = syscall(2, filep, 577, 420, 0, 0);
    print("open W fd   = ");
    print_i64(fd);
    print_nl();
    if fd < 0 { print("open W FAIL\n"); return 1; }
    n = syscall(1, fd, want, 10, 0, 0, 0);
    print("write bytes = ");
    print_i64(n);
    print_nl();
    syscall(3, fd, 0, 0, 0, 0, 0);
    if n != 10 { ok = 0; }

    # 3) 关掉再打开读回 —— 只有真落盘了才读得到
    fd = syscall(2, filep, 0, 0, 0, 0);
    print("open R fd   = ");
    print_i64(fd);
    print_nl();
    if fd < 0 { print("open R FAIL\n"); return 1; }
    n = syscall(0, fd, &buf, 10, 0, 0, 0);
    print("read bytes  = ");
    print_i64(n);
    print_nl();
    syscall(3, fd, 0, 0, 0, 0, 0);
    print("read back   : ");
    syscall(1, 1, &buf, n, 0, 0, 0);
    if n != 10 { ok = 0; }

    # 4) 查询 —— 包管理要判断"这个包装了没有"。只断言返回值 0（存在），
    #    不解析 struct stat：cfs-* 走 C 生成器，没有 load8 映射，读不了结构体。
    #
    #    stat 是 *at 里参数最多的：newfstatat 要插 dfd **且**尾追加 flags，
    #    所以源码这里只能写 5 个实参（号 + 3 个），否则适配后超出
    #    mo_syscall 的 7 个形参而编译失败（CLAUDE.md 第 13 条）。
    n = syscall(4, filep, &sbuf, 0, 0);
    print("stat ret    = ");
    print_i64(n);
    print_nl();
    if n != 0 { ok = 0; }

    # 5) 删除 —— 卸载 / 清缓存
    n = syscall(87, filep, 0, 0, 0, 0);
    print("unlink ret  = ");
    print_i64(n);
    print_nl();
    if n != 0 { ok = 0; }

    print("pkg ok      = ");
    print_i64(ok);
    print_nl();
    if ok == 1 { return 0; }
    return 1;
}
