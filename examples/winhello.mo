# winhello.mo —— Windows 原生程序示例（用墨语言写）
#
#   bash tools/winbuild.sh examples/winhello.mo /tmp/hello.exe
#
# 同一份源码改一下后端就能编成 Linux ELF / Windows PE / ARM64 静态程序。
# mo-target: c-windows   # 非原生后端，projcheck 跳过原生编译
fn main() -> i64 {
    print("Hello from the Mo language\n");
    print("running as a native Windows PE32+ executable\n");
    let i: i64 = 1;
    let s: i64 = 0;
    while i <= 10 {
        s = s + i * i;
        i = i + 1;
    }
    print("sum of squares 1..10 = ");
    print_i64(s);
    print_nl();
    return 0;
}
