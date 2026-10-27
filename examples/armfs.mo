# armfs.mo —— 安卓原生 **文件 IO** 示例（freestanding，不链 libc）
#
#   bash tools/android_native.sh examples/armfs.mo /tmp/armfs
#   adb push /tmp/armfs /data/local/tmp/ && adb shell /data/local/tmp/armfs
#
# 为什么这个例子不可省：包管理器必须读写文件（mo.toml、锁文件、建目录）。
# 在 mo2x 做「x86 号 → *at 号 + 参数重排」适配之前，这些调用在 ARM64 上
# **全部发错号** —— 不报错、不崩溃，只是悄悄干错事（详见 docs/sysno.md）。
#
# 局部数组 buf 是**故意**的：它守护 v1.153 修掉的 _start 栈错位 8 字节缺陷
# （用到局部数组的程序在 cfs-x86_64 上一启动就 SIGSEGV，崩在任何输出之前）。
# mo-target: cfs-aarch64   # 非原生后端，projcheck 跳过原生编译

fn main() -> i64 {
    let path: ptr = "/tmp/mo_armfs.txt";
    let want: ptr = "MO-FS-OK\n";
    let fd: i64 = 0;
    let n: i64 = 0;
    let i: i64 = 0;
    let ok: i64 = 1;
    let buf: [32] i64 = 0;

    # O_WRONLY|O_CREAT|O_TRUNC = 1 | 0x40 | 0x200 = 577；mode 0644 = 420
    fd = syscall(2, path, 577, 420, 0, 0);
    if fd < 0 {
        print("open W FAIL\n");
        return 1;
    }
    n = syscall(1, fd, want, 9, 0, 0, 0);
    syscall(3, fd, 0, 0, 0, 0, 0);
    print("write bytes = ");
    print_i64(n);
    print_nl();

    # 关掉再打开，读回来 —— 只有真的落盘了才能读回
    fd = syscall(2, path, 0, 0, 0, 0);
    if fd < 0 {
        print("open R FAIL\n");
        return 1;
    }
    n = syscall(0, fd, &buf, 9, 0, 0, 0);
    syscall(3, fd, 0, 0, 0, 0, 0);
    print("read bytes  = ");
    print_i64(n);
    print_nl();

    # 把读回的内容**再写到 stdout** —— 由测试脚本 grep 它，
    # 比在程序里自证更可信（自证的程序写错了会一起错）。
    #
    # 不用 load8 逐字节比较：freestanding 后端（cfs-*）走 C 生成器，
    # 没有 load8 的映射（原生后端才有），用它直接编译失败。
    print("read back   : ");
    syscall(1, 1, &buf, n, 0, 0, 0);
    if n != 9 { ok = 0; }
    print("content ok  = ");
    print_i64(ok);
    print_nl();

    # 目录与删除：包管理器建目录、清缓存都要用
    n = syscall(83, "/tmp/mo_armfs_dir", 420, 0, 0);
    print("mkdir ret   = ");
    print_i64(n);
    print_nl();
    n = syscall(87, path, 0, 0, 0);
    print("unlink ret  = ");
    print_i64(n);
    print_nl();

    if ok == 1 { return 0; }
    return 1;
}
