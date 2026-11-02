# len(arr) 内建（v1.1068）：编译期返回数组外层元素个数。
import "io.mo";

fn main() {
    let a: [3] i64 = [1, 2, 3];
    let m: [2][4] i64 = [[1, 2, 3, 4], [5, 6, 7, 8]];
    print(len(a));        # 3
    print(len(m));        # 2（二维取外层）
    print(len(a) * 10 + len(m));   # 32
}
