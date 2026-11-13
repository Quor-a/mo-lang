# expect: 31
# tests/351_sort2_smoke.mo —— lib/sort2 import 引用冒烟（radix 负数排序）
# 排查记录：调试中曾出现 RC=1 假象 —— 是「编译失败后旧 elf 残留被执行」
# （CLAUDE.md 红线）而非代码生成 bug；rm elf 重编后稳定 31。
import "sort2.mo";

fn main() -> i64 {
    if heap_ready() == 0 {
        heap_init();
    }
    let a: i64 = alloc8(4);
    store64(a, 9);
    store64(a + 8, -4);
    store64(a + 16, 0);
    store64(a + 24, 2);
    radix_i64(a, 4);
    let acc: i64 = is_sorted_i64(a, 4);
    let m1: i64 = load64(a) == -4;
    let m2: i64 = load64(a + 8) == 0;
    let m3: i64 = load64(a + 16) == 2;
    let m4: i64 = load64(a + 24) == 9;
    return m1*1 + m2*2 + m3*4 + m4*8 + acc*16;
}
