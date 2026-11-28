import "aes.mo";

var t_fail: i64 = 0;
import "io.mo";

fn eq16(a: ptr, hex: ptr) -> i64 {
    # 逐字节与 hex 串比对
    let i: i64 = 0;
    while i < 16 {
        let hi: i64 = load8(hex + i * 2);
        let lo: i64 = load8(hex + i * 2 + 1);
        let hv: i64 = 0;
        let lv: i64 = 0;
        if hi >= 97 { hv = hi - 87; } else { hv = hi - 48; }
        if lo >= 97 { lv = lo - 87; } else { lv = lo - 48; }
        if load8(a + i) != hv * 16 + lv {
            print("byte ");
            print_i64(i);
            print(" mismatch\n");
            return 0;
        }
        i = i + 1;
    }
    return 1;
}

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

fn assert_eq(cond: i64, msg: str) {
    if cond == 1 {
        print("PASS ");
        print(msg);
        print("\n");
    } else {
        print("FAIL ");
        print(msg);
        print("\n");
        t_fail = t_fail + 1;
    }
}


fn main() -> i64 {
    aes_init();
    # FIPS-197 C.1: AES-128 单块
    let key: [16] byte = 0;
    let inp: [16] byte = 0;
    let outp: [16] byte = 0;
    hexbytes(key, "000102030405060708090a0b0c0d0e0f", 16);
    hexbytes(inp, "00112233445566778899aabbccddeeff", 16);
    let w: [240] byte = 0;
    aes_key_expand(4, key, w);
    aes_block(4, w, inp, outp);
    assert_eq(eq16(outp, "69c4e0d86a7b0430d8cdb78070b4c55a"), "fips197 C.1 aes128 block");
    # 解密回环
    let rt: [16] byte = 0;
    aes_block_dec(4, w, outp, rt);
    assert_eq(eq16(rt, "00112233445566778899aabbccddeeff"), "fips197 C.1 decrypt roundtrip");
    # FIPS-197 C.3: AES-256
    let key256: [32] byte = 0;
    hexbytes(key256, "603deb1015ca71be2b73aef0857d77811f352c073b6108d72d9810a30914dff4", 32);
    let w256: [240] byte = 0;
    aes_key_expand(8, key256, w256);
    aes_block(8, w256, inp, outp);
    assert_eq(eq16(outp, "d83414223d20a0c928b136c884d07ea2"), "fips197 C.3 aes256 block");
    aes_block_dec(8, w256, outp, rt);
    assert_eq(eq16(rt, "00112233445566778899aabbccddeeff"), "fips197 C.3 decrypt roundtrip");
    # ECB 4 块（SP 800-38A F.1.1 ECB-AES128: 明文四块）
    let ecb: [64] byte = 0;
    hexbytes(ecb, "6bc1bee22e409f96e93d7e117393172aae2d8a571e03ac9c9eb76fac45af8e5130c81c46a35ce411e5fbc1191a0a52eff69f2445df4f9b17ad2b417be66c3710", 64);
    let spkey: [16] byte = 0;
    hexbytes(spkey, "2b7e151628aed2a6abf7158809cf4f3c", 16);
    aes_ecb_encrypt(4, spkey, ecb, 64);
    assert_eq(eq16(ecb, "3ad77bb40d7a3660a89ecaf32466ef97"), "sp800-38a ecb128 block1");
    aes_ecb_decrypt(4, spkey, ecb, 64);
    assert_eq(eq16(ecb, "6bc1bee22e409f96e93d7e117393172a"), "sp800-38a ecb128 roundtrip");
    # CTR AES-128 (F.5.1): counter 16B = f0f1...fe 递增 32bit 尾部? NIST: initial counter f0f1f2f3f4f5f6f7f8f9fafbfcfdfeff（16B 全用，最后 4B 递增? 实为整 16B 大端递增从 ff 端）。我们的 CTR 从 ctr[15] 递增——NIST 计数器=最低有效 32 位？F.5.1 描述 increment least significant 32 bits。我们递增从 byte15——语义差异只在计数器溢出进位范围（4 块内无影响）。
    let ctr_data: [64] byte = 0;
    let nonce: [16] byte = 0;
    hexbytes(nonce, "f0f1f2f3f4f5f6f7f8f9fafbfcfdfeff", 16);
    hexbytes(ctr_data, "6bc1bee22e409f96e93d7e117393172aae2d8a571e03ac9c9eb76fac45af8e5130c81c46a35ce411e5fbc1191a0a52eff69f2445df4f9b17ad2b417be66c3710", 64);
    aes_ctr(4, spkey, nonce, ctr_data, 64);
    assert_eq(eq16(ctr_data, "874d6191b620e3261bef6864990db6ce"), "sp800-38a ctr128 block1");
    if t_fail == 0 {
        print("ALL PASS\n");
        return 0;
    }
    print_i64(t_fail);
    print(" FAILS\n");
    return 1;
}
