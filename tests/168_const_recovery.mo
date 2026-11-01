# expect: 7
# 测试：const 错误软恢复 + errors 覆盖（v1.1006）
# 正常路径回归：const Y 在错误 const X 之后仍正确定义（见 errors/e26/e27）。
const Y: i64 = 7;

fn main() -> i64 {
    return Y;
}
