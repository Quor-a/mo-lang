# uefi.mo —— 用墨语言写的 UEFI 应用（64 位固件环境）
#
#   bash tools/uefi.sh examples/uefi.mo /tmp/mouefi.efi
#
# 与 32 位 Multiboot 内核（examples/kernel.mo）的区别：
#   那里是"自己接管硬件"（写 VGA 0xB8000、in/out 端口），
#   这里是"跟固件合作"（走 EFI_SIMPLE_TEXT_OUTPUT_PROTOCOL）。
#
# 与 cfs/kern 后端的区别：UEFI 既没有 Linux 系统调用，也没有 VGA 缓冲。
# 所以 print_i64() 在这里是调用 ConOut->OutputString —— 同一个函数名，
# 三种后端三种实现。
#
# mo-target: uefi   # 非原生后端，projcheck 跳过原生编译

fn fib(n: i64) -> i64 {
    if n < 2 { return n; }
    return fib(n - 1) + fib(n - 2);
}

fn main() -> i64 {
    print("Mo UEFI application\r\n");
    print("running in the firmware environment\r\n");
    print("\r\n");

    let i: i64 = 0;
    print("fib: ");
    while i < 15 {
        print_i64(fib(i));
        print(" ");
        i = i + 1;
    }
    print("\r\n");

    # 展示一下整数计算在固件里同样可用
    let s: i64 = 0;
    i = 1;
    while i <= 100 {
        s = s + i;
        i = i + 1;
    }
    print("sum 1..100 = ");
    print_i64(s);
    print("\r\n");

    return 0;
}
