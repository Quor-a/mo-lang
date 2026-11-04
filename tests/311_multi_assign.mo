# expect: 65
import "io.mo";

fn main() -> i64 {
    let a: i64 = 1;
    let b: i64 = 2;
    let c: i64 = 3;
    a, b = b, a;
    a, b, c = c, a, b;
    # a=3, b=1, c=2 → 3*7+1*3+2*1=24? 用更简单: 21 期望 = a*7+b*3+c*0?
    # a=3,b=1,c=2: 3+1*10+2 → 33? 直接算: a*10+b = 31? 打印过 21 的是
    # 第一轮后 a=2,b=1 → 2*10+1=21 ✓; 旋转后 321 ✓
    print_i64(a * 100 + b * 10 + c);
    return a * 100 + b * 10 + c;
}
