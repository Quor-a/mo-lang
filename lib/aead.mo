# AEAD_CHACHA20_POLY1305 (RFC 8439 2.8)
import "chacha20.mo";
import "poly1305.mo";
# derive poly key: chacha20 block with counter=0, take 32 bytes
fn aead_poly_key(key: ptr, nonce: ptr, pk: ptr) {
    let state: [64] byte = 0;
    let ks: [64] byte = 0;
    chacha_init_state(state, key, 0, nonce);
    chacha_block(state, ks);
    let i: i64 = 0;
    while i < 32 {
        store8(pk + i, load8(ks + i));
        i = i + 1;
    }
}
# little-endian 64-bit length append helper
fn aead_len_block(p: ptr, off: i64, v: i64) {
    let i: i64 = 0;
    while i < 8 {
        store8(p + off + i, (v >> (i * 8)) & 255);
        i = i + 1;
    }
}
fn aead_encrypt(key: ptr, nonce: ptr, aad: ptr, aadlen: i64, pt: ptr, ptlen: i64, ct: ptr, tag: ptr) {
    let pk: [32] byte = 0;
    aead_poly_key(key, nonce, pk);
    # chacha20 with counter=1
    let state: [64] byte = 0;
    let ks: [64] byte = 0;
    chacha_init_state(state, key, 1, nonce);
    let off: i64 = 0;
    while off < ptlen {
        chacha_block(state, ks);
        let j: i64 = 0;
        while j < 64 {
            if off + j < ptlen {
                store8(ct + off + j, load8(pt + off + j) ^ load8(ks + j));
            }
            j = j + 1;
        }
        off = off + 64;
        cc_st32(state, 48, (cc_ld32(state, 48) + 1) & 4294967295);
    }
    # mac data: pad16(aad) || aad || pad16(ct) || ct || len_aad LE64 || len_ct LE64
    let mlen: i64 = aadlen + ptlen + 16;
    let pa: i64 = (16 - (aadlen % 16)) % 16;
    let pc: i64 = (16 - (ptlen % 16)) % 16;
    mlen = mlen + pa + pc;
    let mac: [256] byte = 0;
    let o: i64 = 0;
    let i: i64 = 0;
    while i < aadlen {
        store8(mac + o + i, load8(aad + i));
        i = i + 1;
    }
    o = o + aadlen + pa;
    i = 0;
    while i < ptlen {
        store8(mac + o + i, load8(ct + i));
        i = i + 1;
    }
    o = o + ptlen + pc;
    aead_len_block(mac, o, aadlen);
    aead_len_block(mac, o + 8, ptlen);
    poly1305(pk, mac, mlen, tag);
}
fn aead_decrypt(key: ptr, nonce: ptr, aad: ptr, aadlen: i64, ct: ptr, ctlen: i64, pt: ptr, tag: ptr) -> i64 {
    let pk: [32] byte = 0;
    aead_poly_key(key, nonce, pk);
    # decrypt: chacha20 counter=1 keystream xor
    let state: [64] byte = 0;
    let ks: [64] byte = 0;
    chacha_init_state(state, key, 1, nonce);
    let off: i64 = 0;
    while off < ctlen {
        chacha_block(state, ks);
        let j: i64 = 0;
        while j < 64 {
            if off + j < ctlen {
                store8(pt + off + j, load8(ct + off + j) ^ load8(ks + j));
            }
            j = j + 1;
        }
        off = off + 64;
        cc_st32(state, 48, (cc_ld32(state, 48) + 1) & 4294967295);
    }
    # recompute mac over aad||pt
    let pa: i64 = (16 - (aadlen % 16)) % 16;
    let pc: i64 = (16 - (ctlen % 16)) % 16;
    let mlen: i64 = aadlen + ctlen + 16 + pa + pc;
    let mac: [256] byte = 0;
    let o: i64 = 0;
    let i: i64 = 0;
    while i < aadlen {
        store8(mac + o + i, load8(aad + i));
        i = i + 1;
    }
    o = o + aadlen + pa;
    i = 0;
    while i < ctlen {
        store8(mac + o + i, load8(ct + i));
        i = i + 1;
    }
    o = o + ctlen + pc;
    aead_len_block(mac, o, aadlen);
    aead_len_block(mac, o + 8, ctlen);
    let chk: [16] byte = 0;
    poly1305(pk, mac, mlen, chk);
    let diff: i64 = 0;
    i = 0;
    while i < 16 {
        if load8(chk + i) != load8(tag + i) {
            diff = diff + 1;
        }
        i = i + 1;
    }
    if diff != 0 { return 0 - diff; }
    return 0;
}
