# expect-error: duplicate definition
const A: i64 = 1;
const A: i64 = 2;
fn main() -> i64 { return 0; }
