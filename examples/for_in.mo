# for-in 数组遍历（v1.1070）
import "io.mo";

fn main() {
    let a: [3] i64 = [10, 20, 30];
    let s: i64 = 0;
    for x in a {
        s = s + x;
    }
    print_i64(s);        # 60
    print("\n");
    let m: [2][2] i64 = [[1, 2], [3, 4]];
    for row in m {
        print_i64(row[0] + row[1]);   # 3, 7
        print("\n");
    }
}
