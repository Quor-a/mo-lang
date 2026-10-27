import "ev.mo";
import "io.mo";
# expect: 0

var CALLS: i64 = 0;
fn cb1(arg: i64) -> i64 { CALLS = CALLS + 1; return arg; }
fn cb2(arg: i64) -> i64 { CALLS = CALLS + 10; return 0; }

fn main() -> i64 {
    if ev_once(2, &cb1) < 0 { print("reg fail\n"); return 1; }
    if ev_on(2, &cb2) < 0 { print("reg fail\n"); return 1; }
    let r1: i64 = ev_emit(2, 7);
    if r1 != 7 { print("fail r1="); print_i64(r1); print("\n"); return 1; }
    let r2: i64 = ev_emit(2, 7);
    if r2 != 0 { print("fail r2="); print_i64(r2); print("\n"); return 1; }
    if CALLS != 21 { print("fail calls="); print_i64(CALLS); print("\n"); return 1; }
    print("EVONCE_OK\n");
    return 0;
}
