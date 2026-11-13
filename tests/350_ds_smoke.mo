# expect: 7
# tests/350_ds_smoke.mo —— lib/ds import 引用冒烟（set+stack 最小回路）
import "ds.mo";

fn main() -> i64 {
    let s: i64 = set_new();
    set_add(s, 42);
    set_add(s, 7);
    set_add(s, 42);
    let acc: i64 = set_has(s, 42) + (set_len(s) == 2) * 2;
    let st: i64 = stack_new();
    stack_push(st, 5);
    stack_push(st, 9);
    acc = acc + (stack_pop(st) == 9) * 4;
    return acc;
}
