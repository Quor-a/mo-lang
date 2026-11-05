# expect: 1
import "io.mo";
fn main() -> i64 {
    # v1.1148: argc/argv 基线 —— run 模式 (moc p.mo run a b) 时
    # argc=3 且 argv(1)="a"，普通运行 argc=1；此用例验证基线。
    let n = argc();
    if n == 1 { return 1; }
    if n == 3 { return 3; }
    return 2;
}
