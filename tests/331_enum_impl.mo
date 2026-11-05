# expect: 15
import "io.mo";
enum Op { Add(i64); Sub(i64); None; }
impl Op {
    fn apply(self, x: i64) -> i64 {
        match self {
            Add(k) => { return k + x; }
            Sub(k) => { return k - x; }
            _ => { return 0 - 1; }
        }
    }
    fn twice(self) -> i64 {
        return self.apply(100) + self.apply(1);
    }
}
fn main() -> i64 {
    let a = Op.Add(10);
    let b = Op.Sub(30);
    # apply: 10+5=15；twice: (30-100)+(30-1)=-41
    if b.twice() == 0 - 41 { return a.apply(5); }
    return 200;
}
