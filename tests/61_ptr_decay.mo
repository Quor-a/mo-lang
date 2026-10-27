# 数组名在表达式里退化为指针 —— 此前 `let p: ptr = buf;` 会把 buf 的
# 前 8 个字节当成地址，于是 p 是垃圾值（通常 0），一解引用就段错误。
# 编译期不报错，是最难查的那类问题。
# expect: 1
import "assert.mo";

fn main() -> i64 {
    let buf: [8] byte = 0;
    let p: ptr = buf;

    # 写入
    p[0] = 65;
    p[1] = 66;

    # 三种读法应一致
    assert_eq("load8", load8(p), 65);
    assert_eq("load8+1", load8(p + 1), 66);
    assert_eq("p[0]", p[0], 65);
    assert_eq("p[1]", p[1], 66);

    # 通过原数组也能看到同一份内存（说明退化的是地址，不是拷贝）
    assert_eq("buf[0]", buf[0], 65);
    assert_eq("buf[1]", buf[1], 66);

    # 反过来改原数组，指针也看得到
    buf[2] = 67;
    assert_eq("p[2]", p[2], 67);

    # &buf 与 buf 都应得到同一个地址
    let q: ptr = &buf;
    assert_eq("q[0]", q[0], 65);
    let t_failed: i64 = test_done();
    if t_failed != 0 { return 2; }
    return 1;
}
