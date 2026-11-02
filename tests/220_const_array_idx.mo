# expect: 25
# const 数组编译期下标（v1.1046）：const S = A[0]+A[2] 走 O_DATA 镜像取值。
const A: [3] i64 = [5, 6, 7];
const S: i64 = A[0] + A[2];
fn main() -> i64 {
    return A[1] + A[2] + S;
}
