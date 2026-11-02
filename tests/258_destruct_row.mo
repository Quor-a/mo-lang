# expect: 7
# 多维数组行绑定解构（v1.1076）：let [r0, r1] = m; 行整块拷贝。
fn main() -> i64 {
    let m: [2][3] i64 = [[1,2,3],[4,5,6]];
    let [r0, r1] = m;
    return r0[0] + r1[2];
}
