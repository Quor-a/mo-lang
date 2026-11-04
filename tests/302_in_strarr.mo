# expect: 9
import "io.mo";

fn main() -> i64 {
    let names: [3] ptr = ["alice", "bob", "carol"];
    let nums: [4] i64 = [7, 8, 9, 10];
    let r: i64 = 0;
    if "bob" in names { r = r + 1; }
    if "dave" in names { r = r + 2; }
    if "alice" not in names { r = r + 4; }
    if "carol" in names { r = r + 8; }
    if 9 in nums { r = r + 16; }
    if 99 in nums { r = r + 32; }
    print_i64(r);
    return r;
}
