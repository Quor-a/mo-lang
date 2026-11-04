# expect: 16
import "io.mo";
import "str.mo";

fn tail2(s: ptr) -> ptr {
    return s + 2;
}

fn main() -> i64 {
    # len("hello")=5, len(ptr)=6, len(arr)=3, len(expr)=2, len("")=0 → 16
    let r: i64 = 0;
    r = r + len("hello");
    let s: ptr = "world!";
    r = r + len(s);
    let a: [3] i64 = [7, 8, 9];
    r = r + len(a);
    r = r + len(tail2("abcd"));
    r = r + len("");
    print_i64(r);
    return r;
}
