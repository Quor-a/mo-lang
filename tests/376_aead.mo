import "aead.mo";
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
    let aad: [12] byte = 0;
    let pt: [114] byte = 0;
    let ct: [114] byte = 0;
    let rt: [114] byte = 0;
    let tag: [16] byte = 0;
    hexbytes(key, "808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9f", 32);
    hexbytes(nonce, "070000004041424344454647", 12);
    hexbytes(aad, "50515253c0c1c2c3c4c5c6c7", 12);
    let s: ptr = "Ladies and Gentlemen of the class of '99: If I could offer you only one tip for the future, sunscreen would be it.";
    let i: i64 = 0;
    while i < 114 { store8(pt + i, load8(s + i)); i = i + 1; }
    # poly key test (RFC 8439 2.8.2: counter=0, nonce=000000000001020304050607? 2.6.2 nonce=000000000001020304050607)
    let pk: [32] byte = 0;
    let nonce2: [12] byte = 0;
    hexbytes(nonce2, "000000000001020304050607", 12);
    let pk2: [32] byte = 0;
    aead_poly_key(key, nonce2, pk2);
    if eq8(pk2, "8ad5a08b905f81cc815040274ab29471a833b637e3fd0da508dbb8e2fdd1a646", 32) == 0 {
        print("PASS poly keygen 2.6.2");
    } else { print("FAIL poly keygen 2.6.2"); t_fail = t_fail + 1; }
    aead_poly_key(key, nonce, pk);
    if eq8(pk, "7bac2b252db447af09b67a55a4e955840ae1d6731075d9eb2a9375783ed553ff", 32) == 0 {
        print("PASS poly keygen");
    } else { print("FAIL poly keygen"); t_fail = t_fail + 1; }
    aead_encrypt(key, nonce, aad, 12, pt, 114, ct, tag);
    if eq8(ct, "d31a8d34648e60db7b86afbc53ef7ec2a4aded51296e08fea9e2b5a736ee62d63dbea45e8ca9671282fafb69da92728b1a71de0a9e060b2905d6a5b67ecd3b3692ddbd7f2d778b8c9803aee328091b58fab324e4fad675945585808b4831d7bc3ff4def08e4b7a9de576d26586cec64b6116", 114) == 0 {
        print("PASS aead ct");
    } else { print("FAIL aead ct"); t_fail = t_fail + 1; }
    if eq8(tag, "1ae10b594f09e26a7e902ecbd0600691", 16) == 0 {
        print("PASS aead tag");
    } else { print("FAIL aead tag"); t_fail = t_fail + 1; }
    if aead_decrypt(key, nonce, aad, 12, ct, 114, rt, tag) == 0 && eq8(rt, "4c616469657320616e642047656e746c656d656e206f662074686520636c617373", 16) == 0 {
        print("PASS aead roundtrip");
    } else { print("FAIL aead roundtrip"); t_fail = t_fail + 1; }
    if t_fail == 0 { print("ALL PASS"); return 0; }
    print_i64(t_fail);
    print(" FAILS");
    return 1;
}
