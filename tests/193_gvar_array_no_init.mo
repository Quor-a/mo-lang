# expect: 0
# 测试：全局数组省略初始化（v1.1030）—— var G: [N] T; 默认 0 填充
var G: [2] i64;

fn main() -> i64 {
    return G[1];
}
