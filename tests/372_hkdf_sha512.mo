# 372 —— lib/hkdf.mo：HKDF-SHA512 RFC 5869 向量（TC1 短 + TC2 长输入多块）
import "hkdf.mo";
import "assert.mo";
import "io.mo";

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

fn chkhex(name: ptr, got: i64, n: i64, want: ptr) -> i64 {
    let wantb: [128] byte = 0;
    hexin(&wantb, want, n);
    let ok: i64 = 1;
    let i: i64 = 0;
    while i < n {
        if (load8(got + i) & 255) != (wantb[i] & 255) { ok = 0; }
        i = i + 1;
    }
    assert_eq(name, ok, 1);
    return 0;
}

fn main() -> i64 {
    # TC1
    let ikm1: [22] byte = 0;
    let i: i64 = 0;
    while i < 22 { ikm1[i] = 11; i = i + 1; }
    let salt1: [13] byte = 0;
    hexin(&salt1, "000102030405060708090a0b0c", 13);
    let info1: [10] byte = 0;
    hexin(&info1, "f0f1f2f3f4f5f6f7f8f9", 10);
    let okm1: [42] byte = 0;
    hkdf_sha512(&salt1, 13, &ikm1, 22, &info1, 10, &okm1, 42);
    chkhex("RFC5869 S512 TC1 okm", &okm1, 42, "832390086cda71fb47625bb5ceb168e4c8e26a1a16ed34d9fc7fe92c1481579338da362cb8d9f925d7cb");

    # TC2：80B 输入，L=128B（两块）
    let ikm2: [80] byte = 0;
    i = 0;
    while i < 80 { ikm2[i] = i; i = i + 1; }
    let salt2: [80] byte = 0;
    hexin(&salt2, "606162636465666768696a6b6c6d6e6f707172737475767778797a7b7c7d7e7f808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9fa0a1a2a3a4a5a6a7a8a9aaabacadaeaf", 80);
    let info2: [80] byte = 0;
    hexin(&info2, "b0b1b2b3b4b5b6b7b8b9babbbcbdbebfc0c1c2c3c4c5c6c7c8c9cacbcccdcecfd0d1d2d3d4d5d6d7d8d9dadbdcdddedfe0e1e2e3e4e5e6e7e8e9eaebecedeeeff0f1f2f3f4f5f6f7f8f9fafbfcfdfeff", 80);
    let okm2: [128] byte = 0;
    hkdf_sha512(&salt2, 80, &ikm2, 80, &info2, 80, &okm2, 128);
    chkhex("RFC5869 S512 TC2 okm", &okm2, 128, "ce6c97192805b346e6161e821ed165673b84f400a2b514b2fe23d84cd189ddf1b695b48cbd1c8388441137b3ce28f16aa64ba33ba466b24df6cfcb021ecff235f6a2056ce3af1de44d572097a8505d9e7a9354e5796284151c2dd39c39b3cd3d8e50fcc383ebdec37476e03b721ef5efef873c281f018b8ca42e1245b2271f87");

    test_done();
    return 0;
}
