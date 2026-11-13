# 358: eprint/eprint_i64/eprint_nl —— stderr 输出与 stdout 分流。
import "io.mo";
fn main() -> i64 {
    print("A\n");
    eprint("E1\n");
    eprint_i64(1234567);
    eprint_nl();
    eprint_i64(-8);
    eprint_nl();
    print("B\n");
    return 0;
}
