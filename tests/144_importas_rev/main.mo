# expect: 123
import "ambB.mo" as B;
import "ambA.mo" as A;
fn main() -> i64 {
    return A.calla() * 100 + B.callb() * 10 + (A.helper() + B.helper());
}
