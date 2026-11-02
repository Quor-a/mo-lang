# expect: 5
# 测试：void 函数 + ptr 形参数组字段写入（v1.1036）
struct Inner { v: [3] i64; }

fn setv(p: ptr Inner) {
    p.v[1] = 5;
}

fn main() -> i64 {
    let r: Inner;
    setv(&r);
    return r.v[1];
}
