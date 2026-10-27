# jsontest —— JSON 解析器实战验证
# 用 lib/json.mo 解析 JSON，覆盖：字符串/整数/负数/布尔/null/未找到/嵌套/转义/空白/大整数
import "io.mo";
import "str.mo";
import "json.mo";

var FAILS: i64 = 0;
var buf: [512] byte = 0;
var val: [256] byte = 0;

fn chk(name: ptr, ok: i64) -> i64 {
    if ok == 1 {
        print("ok ");
    } else {
        print("FAIL ");
        FAILS = FAILS + 1;
    }
    print(name);
    print_nl();
    return 0;
}

fn main() -> i64 {
    heap_init();

    # --- 基本字符串/整数/负数/布尔/null ---
    strcpy(&buf, "{\"name\":\"mo-lang\",\"ver\":12,\"neg\":-7,\"on\":true,\"off\":false,\"n\":null}");
    let r: i64 = json_str(&buf, "name", &val);
    chk("str name", r * (strcmp(&val, "mo-lang") == 0));
    chk("int ver=12", json_int(&buf, "ver") == 12);
    chk("int neg=-7", json_int(&buf, "neg") == 0 - 7);
    chk("true on", json_true(&buf, "on") == 1);
    chk("false off", json_true(&buf, "off") == 0);

    # --- 未找到 key ---
    chk("miss nokey", json_str(&buf, "nokey", &val) == 0);

    # --- 值里含转义引号：值长度应为 has "quote" inside = 19 ---
    strcpy(&buf, "{\"b\":\"has \\\"quote\\\" inside\",\"c\":3}");
    let r2: i64 = json_str(&buf, "b", &val);
    chk("str with quote len20", r2 * (strlen(&val) == 20));

    # --- 嵌套对象 ---
    strcpy(&buf, "{\"o\":{\"id\":9,\"tag\":\"deep\"},\"top\":\"up\"}");
    chk("nested id=9", json_int(&buf, "id") == 9);
    let r3: i64 = json_str(&buf, "tag", &val);
    chk("nested tag=deep", r3 * (strcmp(&val, "deep") == 0));
    let r4: i64 = json_str(&buf, "top", &val);
    chk("nested top=up", r4 * (strcmp(&val, "up") == 0));

    # --- 数组后字段 / 大整数 ---
    strcpy(&buf, "{\"arr\":[1,22,333],\"after\":5}");
    chk("arr after=5", json_int(&buf, "after") == 5);
    strcpy(&buf, "{\"big\":123456789012}");
    chk("big int", json_int(&buf, "big") == 123456789012);

    # --- 空白容忍 ---
    strcpy(&buf, "{  \"sp\" :   42  ,  \"sq\" : \"v v\" }");
    chk("ws int=42", json_int(&buf, "sp") == 42);
    let r5: i64 = json_str(&buf, "sq", &val);
    chk("ws str", r5 * (strcmp(&val, "v v") == 0));

    print("fails=");
    print_i64(FAILS);
    print_nl();
    if FAILS > 0 { return 1; }
    return 0;
}
