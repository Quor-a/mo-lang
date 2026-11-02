# do { ... } while (cond);（v1.1071）：至少执行一次。
import "io.mo";

fn main() {
    let n: i64 = 0;
    do {
        n = n + 1;
    } while (n < 3);
    print_i64(n);        # 3
    print("\n");
    do {
        print("once\n");
    } while (0);         # 条件假也执行一次
}
