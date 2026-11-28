import "chacha20.mo";
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
    let nonce: [12] byte = 0;
    let pt: [128] byte = 0;
    let ct: [128] byte = 0;
    hexbytes(key, "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f", 32);
    hexbytes(nonce, "000000000000004a00000000", 12);
    let s: ptr = "Ladies and Gentlemen of the class of '99: If I could offer you only one tip for the future, sunscreen would be it.";
    let i: i64 = 0;
    let mlen: i64 = 114;
    while i < mlen { store8(pt + i, load8(s + i)); i = i + 1; }
    chacha20(key, nonce, pt, ct, mlen);
    if eq8(ct, "6e2e359a2568f98041ba0728dd0d6981e97e7aec1d4360c20a27afccfd9fae0b", 32) == 0 {
        print("PASS rfc8439 2.2.2 chacha20 block1");
    } else { print("FAIL rfc8439 ct block1"); t_fail = t_fail + 1; }
    if eq8(ct + 112, "874d", 2) == 0 {
        print("PASS rfc8439 2.4.2 tail");
    } else { print("FAIL tail"); t_fail = t_fail + 1; }
    if t_fail == 0 { print("ALL PASS"); return 0; }
    print_i64(t_fail);
    print(" FAILS");
    return 1;
}
