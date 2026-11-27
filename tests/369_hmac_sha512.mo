# 369 —— lib/hmac.mo：HMAC-SHA512（RFC 4231 TC1~TC6 全向量，含 >block-size key）
import "hmac.mo";
import "assert.mo";

fn hexin(dst: i64, s: ptr, n: i64) -> i64 {
    let i: i64 = 0;
    while i < n {
        let c1: i64 = load8(s + i * 2);
        let c2: i64 = load8(s + i * 2 + 1);
        let v1: i64 = 0;
        let v2: i64 = 0;
        if c1 >= 97 { v1 = c1 - 87; }
        if c1 < 97 { v1 = c1 - 48; }
        if c2 >= 97 { v2 = c2 - 87; }
        if c2 < 97 { v2 = c2 - 48; }
        store8(dst + i, v1 * 16 + v2);
        i = i + 1;
    }
    return 0;
}

fn check(name: ptr, got: i64, want_hex: ptr) -> i64 {
    let want: [64] byte = 0;
    hexin(&want, want_hex, 64);
    let ok: i64 = 1;
    let i: i64 = 0;
    while i < 64 {
        if (load8(got + i) & 255) != (want[i] & 255) { ok = 0; }
        i = i + 1;
    }
    assert_eq(name, ok, 1);
    return 0;
}

fn main() -> i64 {
    # TC1: key=0x0b*20, data="Hi There"
    let k1: [20] byte = 0;
    let i: i64 = 0;
    while i < 20 { k1[i] = 11; i = i + 1; }
    let out: [64] byte = 0;
    hmac_sha512(&k1, 20, "Hi There", 8, &out);
    check("RFC4231 TC1", &out, "87aa7cdea5ef619d4ff0b4241a1d6cb02379f4e2ce4ec2787ad0b30545e17cdedaa833b7d6b8a702038b274eaea3f4e4be9d914eeb61f1702e696c203a126854");

    # TC2: key="Jefe", data="what do ya want for nothing?"
    hmac_sha512("Jefe", 4, "what do ya want for nothing?", 28, &out);
    check("RFC4231 TC2", &out, "164b7a7bfcf819e2e395fbe73b56e0a387bd64222e831fd610270cd7ea2505549758bf75c05a994a6d034f65f8f0e6fdcaeab1a34d4a6b4b636e070a38bce737");

    # TC3: key=0xaa*20, data=0xdd*50
    let k3: [20] byte = 0;
    i = 0;
    while i < 20 { k3[i] = 0xaa; i = i + 1; }
    let d3: [50] byte = 0;
    i = 0;
    while i < 50 { d3[i] = 0xdd; i = i + 1; }
    hmac_sha512(&k3, 20, &d3, 50, &out);
    check("RFC4231 TC3", &out, "fa73b0089d56a284efb0f0756c890be9b1b5dbdd8ee81a3655f83e33b2279d39bf3e848279a722c806b485a47e67c807b946a337bee8942674278859e13292fb");

    # TC4: key=1..25, data=0xcd*50
    let k4: [25] byte = 0;
    i = 0;
    while i < 25 { k4[i] = i + 1; i = i + 1; }
    let d4: [50] byte = 0;
    i = 0;
    while i < 50 { d4[i] = 0xcd; i = i + 1; }
    hmac_sha512(&k4, 25, &d4, 50, &out);
    check("RFC4231 TC4", &out, "b0ba465637458c6990e5a8c5f61d4af7e576d97ff94b872de76f8050361ee3dba91ca5c11aa25eb4d679275cc5788063a5f19741120c4f2de2adebeb10a298dd");

    # TC5: key=0xaa*131 (>block), data="Test Using Larger Than Block-Size Key - Hash Key First"
    let k5: [131] byte = 0;
    i = 0;
    while i < 131 { k5[i] = 0xaa; i = i + 1; }
    hmac_sha512(&k5, 131, "Test Using Larger Than Block-Size Key - Hash Key First", 54, &out);
    check("RFC4231 TC5", &out, "80b24263c7c1a3ebb71493c1dd7be8b49b46d1f41b4aeec1121b013783f8f3526b56d037e05f2598bd0fd2215d6a1e5295e64f73f63f0aec8b915a985d786598");

    # TC6: key="aa"*131, data 长消息 (>block key + >block data)
    let k6: [131] byte = 0;
    i = 0;
    while i < 131 { k6[i] = 0xaa; i = i + 1; }
    let d6: [152] byte = 0;
    let m6: ptr = "This is a test using a larger than block-size key and a larger than block-size data. The key needs to be hashed before being used by the HMAC algorithm.";
    i = 0;
    while i < 152 { d6[i] = load8(m6 + i); i = i + 1; }
    hmac_sha512(&k6, 131, &d6, 152, &out);
    check("RFC4231 TC6", &out, "e37b6a775dc87dbaa4dfa9f96e5e3ffddebd71f8867289865df5a32d20cdc944b6022cac3c4982b10d5eeb55c3e4de15134676fb6de0446065c97440fa8c6a58");

    test_done();
    return 0;
}
