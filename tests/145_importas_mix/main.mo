# expect: 15
import "ambA.mo" as A;
import "g.mo";
fn main() -> i64 {
    return A.helper() * 10 + gfun();
}
