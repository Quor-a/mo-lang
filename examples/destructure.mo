# 数组解构 let [x, y, z] = arr;（v1.1073）
import "io.mo";

fn main() {
    let a: [3] i64 = [10, 20, 30];
    let [x, y, z] = a;
    print_i64(x);
    print(",");
    print_i64(y);
    print(",");
    print_i64(z);
    print("\n");
}
