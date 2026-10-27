# pack：字节序与宽度。数据用已知值手写，不依赖任何外部工具。
# expect: 1
import "pack.mo";
import "assert.mo";

var B: [16] byte = 0;

fn main() -> i64 {
    # 0x12345678 在小端下是 78 56 34 12，大端下是 12 34 56 78
    pack_u32le(&B, 305419896);
    assert_eq("a1", load8(&B), 120);
    assert_eq("a2", load8(&B + 1), 86);
    assert_eq("a3", load8(&B + 2), 52);
    assert_eq("a4", load8(&B + 3), 18);
    assert_eq("a5", unpack_u32le(&B), 305419896);

    pack_u32be(&B + 4, 305419896);
    assert_eq("a6", load8(&B + 4), 18);
    assert_eq("a7", load8(&B + 5), 52);
    assert_eq("a8", load8(&B + 6), 86);
    assert_eq("a9", load8(&B + 7), 120);
    assert_eq("a10", unpack_u32be(&B + 4), 305419896);

    # 关键：用**错误的**字节序读同一个缓冲，值必须不同。
    # 若某一支写反了（le/be 实现相同），这里就会相等 —— 这是最有效的判别。
    assert_true("endianness matters", unpack_u32be(&B) != unpack_u32le(&B));

    # 16 位
    pack_u16le(&B + 8, 4660);       # 0x1234
    assert_eq("a11", load8(&B + 8), 52);
    assert_eq("a12", load8(&B + 9), 18);
    assert_eq("a13", unpack_u16le(&B + 8), 4660);
    pack_u16be(&B + 10, 4660);
    assert_eq("a14", unpack_u16be(&B + 10), 4660);

    # 有符号：0xFFFFFFFF 作为 i32 是 -1
    pack_u32le(&B + 12, 4294967295);
    assert_eq("a15", unpack_i32le(&B + 12), -1);
    assert_eq("a16", unpack_u32le(&B + 12), 4294967295);   # 无符号读回原值
    let t_failed: i64 = test_done();
    if t_failed != 0 { return 2; }
    return 1;
}
