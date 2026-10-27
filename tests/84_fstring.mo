# 84 —— 字符串插值 f"..."
#
# print(f"共 {n} 篇")  展开为  print("共 "); print_i64(n); print(" 篇");
#
# 插值项按**表达式类型**自动分派：i64 → print_i64，字符串 → print。
#
# 只验证"能编译跑通"；逐字节比对在 tools/fstrtest.sh 里
# （与手写 print / print_i64 的输出对照）。
import "io.mo";

fn main() -> i64 {
    let n: i64 = 7;
    let a: i64 = 3;
    let b: i64 = 4;
    let name: ptr = "world";

    print(f"共 {n} 篇\n");
    print(f"{a} + {b} = 7\n");
    print(f"a*b = {a * b}\n");
    print(f"sum = {a + b + n}\n");
    print(f"plain\n");
    print(f"{n}\n");
    print(f"x{n}y\n");
    # 字符串变量插值
    print(f"hello {name}\n");
    print(f"{name} has {n}\n");
    # 字符串字面量直接插值
    print(f"lit {"direct"}\n");
    return 0;
}
