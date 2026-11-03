# expect: 142
# 解构 RHS 函数调用（v1.1089）：let [x, y, z] = mk();（返回值=全局数组地址存隐藏槽）
let g: [3] i64 = [4,5,6];

fn mk() -> [3] i64 {
    return g;
}

fn main() -> i64 {
    let [x, y, z] = mk();
    return x + y*10 + z*100;
}
