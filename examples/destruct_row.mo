# 多维数组行绑定解构（v1.1076）：行整块拷贝到新变量。
import "io.mo";

fn main() {
    let m: [2][3] i64 = [[1,2,3],[4,5,6]];
    let [r0, r1] = m;
    print_i64(r0[0]);
    print(",");
    print_i64(r1[2]);
    print("\n");
}
