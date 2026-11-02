# 字符串方法语法（v1.1074）：s.trim() → str_trim(s) 等库自由函数前缀回退。
import "str.mo";
import "io.mo";

fn main() {
    let s: str = "  Hello  ";
    print("[");
    print(s.trim());
    print("]");
    print("\n");
}
