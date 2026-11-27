# 368 —— lib/ed25519.mo：Ed25519 验证（RFC 8032 有效签名 ✓ + 篡改拒绝 ✗）
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

fn main() -> i64 {
    ed_init();

    # TEST1 空消息：有效签名应通过
    let pk1: [32] byte = 0;
    hexin(&pk1, "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a", 32);
    let sig1: [64] byte = 0;
    hexin(&sig1, "e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b", 64);
    assert_eq("verify TEST1", ed_verify(&pk1, &pk1, 0, &sig1), 1);

    # TEST2 单字节 0x72
    let pk2: [32] byte = 0;
    hexin(&pk2, "5ccb6692e09be94870c3fa0922676df60c539178031d312c2e6214216b27f97d", 32);
    let sig2: [64] byte = 0;
    hexin(&sig2, "4deefcaa0a105a29bd08c208fe14c1328354838b97e613707dac16e21751bc7f46f40e1352df29e54f0c7cea9e5deb413761b47b875540c75463a4a9f7eace0f", 64);
    let m2: [1] byte = 0;
    m2[0] = 114;
    assert_eq("verify TEST2", ed_verify(&pk2, &m2, 1, &sig2), 1);

    # 篡改消息 → 拒绝
    let m3: [1] byte = 0;
    m3[0] = 115;
    assert_eq("tampered msg rejected", ed_verify(&pk2, &m3, 1, &sig2), 0);

    # 篡改签名（S+1）→ 拒绝
    let sig4: [64] byte = 0;
    let i: i64 = 0;
    while i < 64 {
        sig4[i] = sig2[i];
        i = i + 1;
    }
    sig4[63] = sig4[63] + 1;
    assert_eq("tampered sig rejected", ed_verify(&pk2, &m2, 1, &sig4), 0);

    # 篡改公钥 → 拒绝
    let pk5: [32] byte = 0;
    i = 0;
    while i < 32 {
        pk5[i] = pk2[i];
        i = i + 1;
    }
    pk5[0] = pk5[0] + 1;
    assert_eq("tampered pk rejected", ed_verify(&pk5, &m2, 1, &sig2), 0);

    # sign→verify 闭环：ed_sign 输出能被 ed_verify 验证
    let sk: [32] byte = 0;
    hexin(&sk, "9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60", 32);
    let sig6: [64] byte = 0;
    ed_sign(&sk, "hello world", 11, &sig6);
    let pk6: [32] byte = 0;
    ed_pubkey(&sk, &pk6);
    assert_eq("sign-verify roundtrip", ed_verify(&pk6, "hello world", 11, &sig6), 1);

    test_done();
    return 0;
}
