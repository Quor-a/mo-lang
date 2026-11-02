# expect: 7
# len() 扩展（v1.1080）：len(str)=运行时 strlen；len(多维数组)=最外维。
# (5 + 2) mod 256 = 7
import "str.mo";

fn main() -> i64 {
    let s: str = "hello";
    let m: [2][3] i64 = [[1,2,3],[4,5,6]];
    return len(s) + len(m);
}
