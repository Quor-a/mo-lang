# expect: 59
import "io.mo";
import "str.mo";

fn main() -> i64 {
    let n: i64 = 0;
    for c in "abcdef" {
        if c == 99 { continue; }
        if c == 102 { break; }
        n = n + 1;
    }
    let pairs: i64 = 0;
    for c1 in "ab" {
        for c2 in "xy" {
            pairs = pairs + 1;
        }
    }
    let first: i64 = 0;
    for c3 in "zebra" {
        first = 1;
        break;
    }
    # n=4, pairs=4, first=1 → 46
    print_i64(n * 8 + pairs * 3 + first + 14);
    return n * 8 + pairs * 3 + first + 14;
}
