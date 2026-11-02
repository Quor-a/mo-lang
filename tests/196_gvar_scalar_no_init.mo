# expect: 9
# 测试：全局标量省略初始化（v1.1032）—— var X: i64; 默认 0
var X: i64;

fn main() -> i64 {
    X = 9;
    return X;
}
