# 测试：顶层 const 声明 + 编译期常量折叠（v1.974）
# const NAME: i64 = 表达式（+ - * / 括号、引用已有 const），编译期求值。
# 使用点直接发 movabs 立即数，不占数据段。
# expect: 32
const MAX: i64 = 10;
const N: i64 = (MAX + 2) * 3 - 4;

fn main() -> i64 {
    return N;
}
