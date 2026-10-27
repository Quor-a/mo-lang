import "ev.mo";
import "io.mo";
# expect: 0

fn cb_a(arg: i64) -> i64 { return arg + 1; }
fn cb_b(arg: i64) -> i64 { return arg * 2; }

var HITS: i64 = 0;
fn cb_hit(arg: i64) -> i64 { HITS = HITS + arg; return 0; }

fn main() -> i64 {
    if ev_on(0, &cb_a) < 0 { print("reg fail\n"); return 1; }
    if ev_on(0, &cb_b) < 0 { print("reg fail\n"); return 1; }
    let r: i64 = ev_emit(0, 5);
    # (5+1) + (5*2) = 16
    if r != 16 { print("fail emit="); print_i64(r); print("\n"); return 1; }
    if ev_on(1, &cb_hit) < 0 { print("reg fail\n"); return 1; }
    ev_emit(1, 3);
    ev_emit(1, 4);
    if HITS != 7 { print("fail hits="); print_i64(HITS); print("\n"); return 1; }
    print("EV_OK\n");
    return 0;
}
