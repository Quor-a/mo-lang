# expect: 6
# 顶层 let 数组声明（v1.1084）：let g: [3] i64 = [1,2,3];（与 var 同义）
let g: [3] i64 = [1,2,3];

fn main() -> i64 {
    return g[0] + g[1] + g[2];
}
