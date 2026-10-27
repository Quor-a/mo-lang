#!/bin/bash
# diag_runtime —— 区分运行时环境差异的具体来源
#
# 在被测程序里直接打印关键环境值，找出 qemu/proot 与原生 Linux 的差别。
cd "$(dirname "$0")/.."
OUT=/tmp/mo_rt; rm -rf $OUT; mkdir -p $OUT/lib; cp lib/*.mo $OUT/lib/
cat > $OUT/test.mo <<'MOEOF'
import "io.mo";
import "mem.mo";
# 1) 未初始化的局部数组：原生 Linux 栈页通常清零，qemu/proot 下不保证
fn probe_stack() -> i64 {
    let a: [8] i64;
    let i: i64 = 0;
    let s: i64 = 0;
    while i < 8 {
        s = s + a[i];
        i = i + 1;
    }
    return s;
}
fn main() -> i64 {
    print("argc      = "); print_i64(argc()); print_nl();
    print("stack_sum = "); print_i64(probe_stack()); print_nl();
    heap_init();
    let p: i64 = alloc(64);
    print("brk_ptr   = "); print_i64(p); print_nl();
    print("heap_used = "); print_i64(heap_used()); print_nl();
    return 0;
}
MOEOF
cd $OUT && ../bin/moc >/dev/null 2>&1 && ./out.elf
echo
echo "参考（x86-64 原生 Linux）："
echo "  argc      = 1"
echo "  stack_sum = 0        <- 若非 0，说明栈未清零，这就是越界的根因"
echo "  brk_ptr   = 一个较大的堆地址"
