import "poly1305.mo";
import "big.mo";
import "io.mo";
fn hexbytes(dst: ptr, hex: ptr, n: i64) {
    let i: i64 = 0;
    while i < n {
        let hi: i64 = load8(hex + i * 2);
        let lo: i64 = load8(hex + i * 2 + 1);
        let hv: i64 = 0;
        let lv: i64 = 0;
        if hi >= 97 { hv = hi - 87; } else { hv = hi - 48; }
        if lo >= 97 { lv = lo - 87; } else { lv = lo - 48; }
        store8(dst + i, hv * 16 + lv);
        i = i + 1;
    }
}
fn eq8(a: ptr, hx: ptr, n: i64) -> i64 {
    let i: i64 = 0;
    while i < n {
        let hi: i64 = load8(hx + i * 2);
        let lo: i64 = load8(hx + i * 2 + 1);
        let hv: i64 = 0;
        let lv: i64 = 0;
        if hi >= 97 { hv = hi - 87; } else { hv = hi - 48; }
        if lo >= 97 { lv = lo - 87; } else { lv = lo - 48; }
        if load8(a + i) != hv * 16 + lv { return 1; }
        i = i + 1;
    }
    return 0;
}
var t_fail: i64 = 0;
fn main() -> i64 {
    let key: [32] byte = 0;
    let msg: [40] byte = 0;
    let tag: [16] byte = 0;
    hexbytes(key, "85d6be7857556d337f4452fe42d506a80103808afb0db2fd4abff6af4149f51b", 32);
    let s: ptr = "Cryptographic Forum Research Group";
    let i: i64 = 0;
    while i < 34 { store8(msg + i, load8(s + i)); i = i + 1; }
    poly1305(key, msg, 34, tag);
    if eq8(tag, "a8061dc1305136c6c22b8baf0c0127a9", 16) == 0 {
        print("PASS rfc8439 2.5.2 poly1305");
    } else {
        print("FAIL poly1305 tag");
        print("tag=");
        i = 0;
        while i < 16 { print_i64(load8(tag + i)); print(","); i = i + 1; }
        print("\n");
        t_fail = t_fail + 1;
    }
    if t_fail == 0 { print("ALL PASS"); return 0; }
    print_i64(t_fail);
    print(" FAILS");
    return 1;
}
