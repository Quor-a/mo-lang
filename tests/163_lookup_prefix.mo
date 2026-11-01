# expect: 42
# 测试：sym_lookup 首字符预过滤优化后回归（v1.1001）
# 重名前缀场景：lib_v 与 lib_w 同首字符，查找不串。
const lib_v: i64 = 42;
const lib_w: i64 = 43;

fn main() -> i64 {
    return lib_v;
}
