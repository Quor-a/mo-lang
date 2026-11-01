# expect: 111
# 测试：const 比较（v1.1003）
# 5>3=1, 2<=2=1, 4==4=1, 4!=4=0 → 1*100+1*10+1-0 = 111
const GT: i64 = 5 > 3;
const LE: i64 = 2 <= 2;
const EQ: i64 = 4 == 4;
const NE: i64 = 4 != 4;

fn main() -> i64 {
    return GT * 100 + LE * 10 + EQ - NE;
}
