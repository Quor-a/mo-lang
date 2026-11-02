# in 运算符（v1.1075）：a in b = a 是 b 的子串。
import "io.mo";

fn main() {
    if "ell" in "hello" {
        print("found\n");
    }
    if "xyz" in "hello" {
        print("bad\n");
    }
}
