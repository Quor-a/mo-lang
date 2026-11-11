# expect: 39
# v1.1163: mo2x C 后端也支持 const fn 求值数组长度（自举编译器已支持）。
# 此测试同时被 moc 与 mo2x 两条链路消费：
#   moc: tests/run.sh 直接编译运行
#   mo2x: bin/mo2x 本文件 c -> C 编译器折叠 mo2x 侧求出的数值维度
const fn fact(n: i64) -> i64 { if n <= 1 { return 1; } return n * fact(n - 1); }
const fn gcd2(a: i64, b: i64) -> i64 { if b == 0 { return a; } return gcd2(b, a % b); }
const N: i64 = 4;
var A: [fact(5)] i64 = 0;        # 120
var B: [gcd2(48,18)] i64 = 0;    # 6
var C: [fact(N)+1] i64 = 0;      # 25
fn main() -> i64 {
    A[119] = 3; B[5] = 9; C[24] = 6;
    let s: i64 = 0;
    s = s + A[119] * 1;
    s = s + B[5] * 2;
    s = s + C[24] * 3;
    # 槽数校验：120 + 6 + 25 = 151
    s = s + (A[0] + B[0] + C[0]) * 0;
    return s % 256;
}
