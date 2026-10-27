# 数组字面量 [1,2,3] 与 byte 数组字符串初始化
import "io.mo";

var GA: [4] i64 = [10, 20, 30, 40];
var GC: [5] i64 = [1, -2, 3];
var GB: [8] byte = "hi!";
var GD: [3] i64 = [7];              # 元素少于长度 → 补 0

fn chk() -> i64 {
    if GA[0] != 10 { return 1; }
    if GA[3] != 40 { return 2; }
    if GC[1] != 0 - 2 { return 3; }      # 负数元素
    if GD[0] != 7 { return 4; }
    if GD[1] != 0 { return 5; }          # 不足补 0
    if GD[2] != 0 { return 6; }
    if GB[0] != 104 { return 7; }        # 'h'
    if GB[1] != 105 { return 8; }        # 'i'
    if GB[2] != 33 { return 9; }         # '!'
    if GB[3] != 0 { return 10; }         # NUL 结尾之后补 0

    # 局部
    let la: [3] i64 = [7, 8, 9];
    let lb: [8] byte = "abc";
    if la[0] != 7 { return 11; }
    if la[2] != 9 { return 12; }
    if lb[0] != 97 { return 13; }        # 'a'
    if lb[2] != 99 { return 14; }        # 'c'
    if lb[3] != 0 { return 15; }
    return 0;
}

fn main() -> i64 {
    print_i64(GA[0]); print(" "); print_i64(GA[3]); print("\n");
    print_i64(GB[0]); print_i64(GB[1]); print_i64(GB[2]); print("\n");
    return chk();
}
