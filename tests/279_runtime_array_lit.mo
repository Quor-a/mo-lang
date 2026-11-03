# expect: 16
# v1.1097: 数组字面量非常量元素 —— 运行期求值（变量/表达式/enum 算术/负号）
import "io.mo";

enum Color { RED; GREEN; BLUE; }

fn main() -> i64 {
    let n: i64 = 5;
    let a: [4] i64 = [n, n+1, n*2, -n];
    print_i64(a[0]);
    print_i64(a[3]);
    let c: [3] i64 = [GREEN * 10, -n, 9];
    print_i64(c[0]);
    print_i64(c[1]);
    return a[0] + a[1] + a[2] + a[3];
}
