# expect: 123
import "ambA.mo" as A;
import "ambB.mo" as B;
fn main() -> i64 {
    return A.calla() * 100 + B.callb() * 10 + (A.helper() + B.helper());
}
