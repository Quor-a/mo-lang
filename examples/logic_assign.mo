# 逻辑复合赋值 &&= ||=（v1.1072）
import "io.mo";

fn main() {
    let ok: i64 = 1;
    ok &&= 1;            # 1
    print_i64(ok);
    print("\n");
    ok &&= 0;            # 0
    print_i64(ok);
    print("\n");
    ok ||= 9;            # 1
    print_i64(ok);
    print("\n");
}
