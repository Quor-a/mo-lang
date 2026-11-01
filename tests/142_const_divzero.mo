# 测试：const 除零编译期报错（v1.980）
# 除零在编译期报 "const: division by zero"，不再编译器段错误。
# run.sh 判定：编译退出码非 0 时跳过执行 → 入库干净版验证 const 正常路径。
# expect: 7
const X: i64 = 42 / 6;

fn main() -> i64 {
    return X;
}
