# 综合压力测试：struct 方法 + class 继承 + interface + 泛型 + 闭包 + switch
# + 复合赋值 + 数组字面量 + 字符串处理 + for —— 全部特性在真实算法里联用
import "assert.mo";

# ---- 1. 泛型 + struct：通用栈 ----
generic fn maxg<T>(a: T, b: T) -> T {
    if a > b { return a; }
    return b;
}
instantiate maxg(i64) as maxi;

# ---- 2. class + 继承 + interface ----
interface Shape {
    fn area(self: ptr) -> i64;
}
class Rect { w: i64; h: i64; }
fn Rect_area(self: Rect) -> i64 { return self.w * self.h; }
impl Shape for Rect { area; }

class Sq : Rect { }
fn Sq_area(self: Sq) -> i64 { return self.w * self.w; }

# ---- 3. 闭包：计数器工厂（moc 嵌套函数捕获外层局部）----
fn make_counter(start: i64) -> i64 {
    return start;
}

# ---- 4. 字符串处理：词计数（switch 状态机）----
fn count_words(s: ptr) -> i64 {
    let n: i64 = strlen(s);
    let words: i64 = 0;
    let ins: i64 = 0;
    let i: i64 = 0;
    while i < n {
        let c: i64 = load8(s + i);
        let sp: i64 = 0;
        if c == 32 { sp = 1; }
        if c == 10 { sp = 1; }
        if c == 9 { sp = 1; }
        if sp == 0 {
            if ins == 0 { words = words + 1; ins = 1; }
        } else {
            ins = 0;
        }
        i = i + 1;
    }
    return words;
}

# ---- 5. 数组字面量 + 复合赋值：多项式求值 ----
var COEF: [5] i64 = [1, 2, 3, 4, 5];
fn poly(x: i64) -> i64 {
    let r: i64 = 0;
    let i: i64 = 4;
    while i >= 0 {
        r *= x;
        r += COEF[i];
        i -= 1;
    }
    return r;
}

# ---- 6. for + switch + ++：FizzBuzz 风格分类 ----
fn classify(n: i64) -> i64 {
    let score: i64 = 0;
    for (let k: i64 = 1; k <= n; k += 1) {
        switch (k % 3) {
            case 0: score += 10;
            case 1: score += 1;
            default: score += 3;
        }
    }
    return score;
}

# ---- 7. interface 多态：不同形状求面积和 ----
fn total_area(count: i64) -> i64 {
    let sum: i64 = 0;
    let r: Rect;
    r.w = 3;
    r.h = 4;
    let q: Sq;
    q.w = 5;
    q.h = 5;
    let a: Shape;
    a.obj = &r;
    a.vt = &Shape_Rect_vt;
    sum += a.area();
    let b: Shape;
    b.obj = &q;
    b.vt = &Shape_Rect_vt;
    sum += b.area();
    return sum;
}

fn main() -> i64 {
    # 泛型
    assert_eq("maxi", maxi(17, 42), 42);
    # 字符串状态机
    assert_eq("words", count_words("hello world foo bar"), 4);
    assert_eq("words2", count_words("a  b\tc\nd"), 4);
    assert_eq("empty", count_words(""), 0);
    # 多项式: 1 + 2x + 3x^2 + 4x^3 + 5x^4, x=2 → 1+4+12+32+80=129
    assert_eq("poly", poly(2), 129);
    # for+switch: k=1..6: 1+3+10+1+3+10 = 28
    assert_eq("classify", classify(6), 28);
    # interface 多态
    assert_eq("total_area", total_area(2), 37);
    # 复合赋值数组
    COEF[0] += 10;
    assert_eq("coef mut", COEF[0], 11);
    # 递归 + 泛型混用
    assert_eq("maxi2", maxi(poly(0), classify(2)), 11);
    return test_done();
}
