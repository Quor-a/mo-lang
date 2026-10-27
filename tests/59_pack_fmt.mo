# pack：格式串驱动。一次读多个字段，验证偏移推进正确。
# expect: 1
import "pack.mo";
import "assert.mo";

var B: [32] byte = 0;
var OUT: [64] i64 = 0;

fn main() -> i64 {
    # 布局：>w（大端 u32） <h（小端 u16） b（1 字节）
    pack_u32be(&B, 258);            # 00 00 01 02
    pack_u16be(&B + 4, 513);        # 02 01
    store8(&B + 6, 7);

    let n: i64 = unpack_fmt(&B, ">w h b", &OUT);   # 空格分隔也要能解析
    assert_eq("a1", n, 7);                # 消耗 4 + 2 + 1 = 7 字节
    assert_eq("a2", load64(&OUT), 258);
    assert_eq("a3", load64(&OUT + 8), 513);
    assert_eq("a4", load64(&OUT + 16), 7);

    # 非法格式串返回 -1
    assert_eq("a5", unpack_fmt(&B, "w", &OUT), -1);      # 缺字节序前缀
    assert_eq("a6", unpack_fmt(&B, "<z", &OUT), -1);     # 未知类型
    let t_failed: i64 = test_done();
    if t_failed != 0 { return 2; }
    return 1;
}
