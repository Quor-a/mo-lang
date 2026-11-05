# expect: 55
# v1.1141: defer 语句 —— 函数退出（return 点）按 LIFO 重放；
# 返回值 rax/rdx 由 push/pop 保护；重放后词法状态恢复，
# parse_block 从原位置继续（否则 let 被二次解析）
import "io.mo";
fn work() -> i64 {
    let x: i64 = 1;
    defer print("d1");
    defer print("d2");
    x = x + 10;
    defer print_i64(x);
    return x * 5;
}
fn main() -> i64 {
    return work();
}
