# 367 —— lib/ed25519.mo：Ed25519 签名 RFC 8032 向量（TEST1 空消息 / TEST2 单字节 / TEST3 16 字节）
import "ed25519.mo";
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

# 64 字节签名 hex 比较（无 NUL 依赖）
fn eq64(a: i64, b: ptr) -> i64 {
    let i: i64 = 0;
    while i < 64 {
        let v: i64 = load8(a + i) & 255;
        let hi: i64 = v >> 4;
        let lo: i64 = v & 15;
        let ch1: i64 = load8(b + i * 2);
        let ch2: i64 = load8(b + i * 2 + 1);
        let w1: i64 = 0;
        let w2: i64 = 0;
        if ch1 >= 97 { w1 = ch1 - 87; }
        if ch1 < 97 { w1 = ch1 - 48; }
        if ch2 >= 97 { w2 = ch2 - 87; }
        if ch2 < 97 { w2 = ch2 - 48; }
        if hi != w1 { return 0; }
        if lo != w2 { return 0; }
        i = i + 1;
    }
    return 1;
}

fn eq32(a: i64, b: ptr) -> i64 {
    let i: i64 = 0;
    while i < 32 {
        let v: i64 = load8(a + i) & 255;
        let hi: i64 = v >> 4;
        let lo: i64 = v & 15;
        let ch1: i64 = load8(b + i * 2);
        let ch2: i64 = load8(b + i * 2 + 1);
        let w1: i64 = 0;
        let w2: i64 = 0;
        if ch1 >= 97 { w1 = ch1 - 87; }
        if ch1 < 97 { w1 = ch1 - 48; }
        if ch2 >= 97 { w2 = ch2 - 87; }
        if ch2 < 97 { w2 = ch2 - 48; }
        if hi != w1 { return 0; }
        if lo != w2 { return 0; }
        i = i + 1;
    }
    return 1;
}

fn main() -> i64 {
    ed_init();

    # TEST1: 空消息
    let sk1: [32] byte = 0;
    hexin(&sk1, "9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60", 32);
    let sig1: [64] byte = 0;
    ed_sign(&sk1, &sk1, 0, &sig1);
    assert_eq("sig1", eq64(&sig1, "e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b"), 1);

    # TEST2: 单字节 0x72
    let sk2: [32] byte = 0;
    hexin(&sk2, "4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed174fb5c1", 32);
    let m2: [1] byte = 0;
    m2[0] = 114;
    let sig2: [64] byte = 0;
    ed_sign(&sk2, &m2, 1, &sig2);
    assert_eq("sig2", eq64(&sig2, "4deefcaa0a105a29bd08c208fe14c1328354838b97e613707dac16e21751bc7f46f40e1352df29e54f0c7cea9e5deb413761b47b875540c75463a4a9f7eace0f"), 1);

    # TEST3: 16 字节 "abcdef0123456789"
    let sk3: [32] byte = 0;
    hexin(&sk3, "c5aa8df43f9f837bedb7442f31dcb7b166d38535076f094b85ce3a2e0b4458f7", 32);
    let sig3: [64] byte = 0;
    ed_sign(&sk3, "abcdef0123456789", 16, &sig3);
    assert_eq("sig3", eq64(&sig3, "6e563dae03980d57ccff7d7322bd5b1ed45adf6af6b3bb00098dbb28840e87eab4362c76ed484424589cdfe7506666ad89ad9aaedbe47590dc64da97a6cc430e"), 1);

    # 公钥推导 TEST1
    let pk1: [32] byte = 0;
    ed_pubkey(&sk1, &pk1);
    assert_eq("pk1", eq32(&pk1, "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a"), 1);

    test_done();
    return 0;
}
