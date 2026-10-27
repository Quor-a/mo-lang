# andromo.mo —— 安卓原生程序示例（用墨语言写，无需 NDK）
#
#   bash tools/android_native.sh examples/andromo.mo /tmp/andromo
#   adb push /tmp/andromo /data/local/tmp/ && adb shell /data/local/tmp/andromo
#
# 它是 freestanding 的：不链接 libc，系统调用用 svc #0 直接陷入内核。
# 所以能在 Android（内核就是 Linux）上直接跑。
# mo-target: cfs-aarch64   # 非原生后端，projcheck 跳过原生编译
fn main() -> i64 {
    print("Mo on Android — native ARM64, no libc\n");

    # 范围可从命令行指定，默认 1000000。
    #
    # 为什么要参数化：朴素筛法对 1000000 要跑约 10^9 次内层迭代，
    # 在 CPU 模拟器里需要几分钟 —— 慢到没法做回归测试。
    # 给个小值（如 20000）就能在毫秒级验证"算得对不对"。
    # 真机上不加参数仍是完整规模。
    # 默认 200000：π(200000) = 17984，是已知值，能在 CPU 模拟器里
    # 几秒内跑完并断言；朴素算法在 1000000 规模下需要约 10^9 次
    # 内层迭代，模拟一次要几分钟，不适合做回归。
    # 真机（Android）上可传参数放大，如 `./andromo 1000000`。
    let n: i64 = 200000;
    if argc() > 1 {
        let v: i64 = atoi(argv(1));
        if v > 1 { n = v; }
    }
    print("counting primes below ");
    print_i64(n);
    print_nl();
    let i: i64 = 2;
    let cnt: i64 = 0;
    while i <= n {
        let d: i64 = 2;
        let prime: i64 = 1;
        while d * d <= i {
            if i - (i / d) * d == 0 { prime = 0; }
            d = d + 1;
        }
        if prime == 1 { cnt = cnt + 1; }
        i = i + 1;
    }
    # 注意别把上限写死在文案里 —— 参数是 200000 时还印 "below 1000000"
    # 属于"数字对但描述错"，会误导读输出的人。
    print("primes below ");
    print_i64(n);
    print(" = ");
    print_i64(cnt);
    print_nl();
    return 0;
}
