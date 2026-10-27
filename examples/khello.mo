# khello.mo —— 用墨语言写的 Linux 内核模块逻辑
#
#   bash tools/kmod.sh examples/khello.mo mokhello
#
# mo2x 把它编成 C，再套 module_init/exit 包装，用内核头文件编译成 .ko。
# 模块加载时会调用这里的 mo_main()。
# mo-target: c-kmod   # 非原生后端，projcheck 跳过原生编译
fn mo_main() -> i64 {
    print("hello from a Mo kernel module\n");
    let i: i64 = 0;
    let s: i64 = 0;
    while i < 100 {
        s = s + i;
        i = i + 1;
    }
    print("sum 0..99 = ");
    print_i64(s);
    print_nl();
    return 0;
}
