# expect: 8
import "io.mo";
fn main() -> i64 {
    # v1.1116: 语句级 enum（局部声明，常量进全局 enum 表）
    enum Fruit { APPLE; PEAR = 5; PEACH; }   # 0 / 5 / 6
    if 1 {
        enum Tmp { A = 100; }
        print_i64(A);                        # 100
    }
    print_i64(PEACH);                        # 6
    let m: i64 = match PEAR { APPLE => 1, PEAR => 2, _ => 3 };
    print_i64(m);                            # 2（match 结果正确）
    return PEACH + 2;                        # 8
}
