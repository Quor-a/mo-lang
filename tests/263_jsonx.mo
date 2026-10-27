import "json.mo";
import "io.mo";
import "str.mo";
# expect: 0

var D: [128] byte = 0;
var E: [128] byte = 0;

fn main() -> i64 {
    let doc: ptr = "{\"name\":\"m\\\"q\\\"o\", \"ver\":\"1.2\", \"n\":42, \"pi\":3.14, \"ok\":true, \"neg\":-2.5}";
    # has
    if json_has(doc, "ver") != 1 { print("fail has\n"); return 1; }
    if json_has(doc, "nope") != 0 { print("fail hasneg\n"); return 1; }
    # int
    if json_int(doc, "n") != 42 { print("fail int\n"); return 1; }
    # 定点小数: pi=3.14 → 31400
    if json_num(doc, "pi") != 31400 { print("fail pi="); print_i64(json_num(doc, "pi")); print("\n"); return 1; }
    if json_num(doc, "neg") != 0 - 25000 { print("fail neg\n"); return 1; }
    # str（含转义引号）
    json_str(doc, "name", &D);
    # 期望 m " q " o（6 字节，含 2 个反斜杠）——用字节校验避开多层转义
    let el: i64 = strlen(&D);
    if el != 7 { print("fail strlen="); print_i64(el); print("\n"); return 1; }
    if load8(&D) != 109 || load8(&D+1) != 92 || load8(&D+2) != 34 || load8(&D+3) != 113 || load8(&D+4) != 92 || load8(&D+5) != 34 || load8(&D+6) != 111 { print("fail bytes\n"); return 1; }
    # escape
    strcpy(&D, "a\"b\nc\td");
    strcpy(&E, &D);
    json_escape(&D, &E);
    if streq(&D, "a\\\"b\\nc\\td") != 1 { print("fail esc:"); print(&D); print("\n"); return 1; }
    print("JSONX_OK\n");
    return 0;
}
