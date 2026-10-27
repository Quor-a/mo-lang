# s390hello.mo
# mo-target: cfs-s390x   # 非原生后端，projcheck 跳过原生编译 —— 用于 s390x 运行时验证的最小程序
#
# 为什么不复用 andromo.mo：它要数素数，在模拟器里约 10 万条指令/秒的
# 速度下太慢。验证"能不能跑"只需要一次 write + 一次 exit。
fn main() -> i64 {
    print("hello from s390x\n");
    return 0;
}
