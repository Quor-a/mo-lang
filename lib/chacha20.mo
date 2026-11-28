# chacha20 stream cipher (RFC 8439)
# byte-buffer based: all state is [N] byte, words are 32-bit LE
fn cc_ld32(p: ptr, o: i64) -> i64 {
    return load8(p + o) | (load8(p + o + 1) << 8) | (load8(p + o + 2) << 16) | (load8(p + o + 3) << 24);
}
fn cc_st32(p: ptr, o: i64, v: i64) {
    store8(p + o, v & 255);
    store8(p + o + 1, (v >> 8) & 255);
    store8(p + o + 2, (v >> 16) & 255);
    store8(p + o + 3, (v >> 24) & 255);
}
fn chacha_qr(s: ptr, a: i64, b: i64, c: i64, d: i64) {
    let x: i64 = 0;
    cc_st32(s, a * 4, (cc_ld32(s, a * 4) + cc_ld32(s, b * 4)) & 4294967295);
    x = cc_ld32(s, d * 4) ^ cc_ld32(s, a * 4);
    cc_st32(s, d * 4, ((x << 16) | (x >> 16)) & 4294967295);
    cc_st32(s, c * 4, (cc_ld32(s, c * 4) + cc_ld32(s, d * 4)) & 4294967295);
    x = cc_ld32(s, b * 4) ^ cc_ld32(s, c * 4);
    cc_st32(s, b * 4, ((x << 12) | (x >> 20)) & 4294967295);
    cc_st32(s, a * 4, (cc_ld32(s, a * 4) + cc_ld32(s, b * 4)) & 4294967295);
    x = cc_ld32(s, d * 4) ^ cc_ld32(s, a * 4);
    cc_st32(s, d * 4, ((x << 8) | (x >> 24)) & 4294967295);
    cc_st32(s, c * 4, (cc_ld32(s, c * 4) + cc_ld32(s, d * 4)) & 4294967295);
    x = cc_ld32(s, b * 4) ^ cc_ld32(s, c * 4);
    cc_st32(s, b * 4, ((x << 7) | (x >> 25)) & 4294967295);
}
fn chacha_rounds(s: ptr) {
    chacha_qr(s, 0, 4, 8, 12);
    chacha_qr(s, 1, 5, 9, 13);
    chacha_qr(s, 2, 6, 10, 14);
    chacha_qr(s, 3, 7, 11, 15);
    chacha_qr(s, 0, 5, 10, 15);
    chacha_qr(s, 1, 6, 11, 12);
    chacha_qr(s, 2, 7, 8, 13);
    chacha_qr(s, 3, 4, 9, 14);
}
fn chacha_init_state(state: ptr, key: ptr, counter: i64, nonce: ptr) {
    cc_st32(state, 0, 1634760805);
    cc_st32(state, 4, 857760878);
    cc_st32(state, 8, 2036477234);
    cc_st32(state, 12, 1797285236);
    let i: i64 = 0;
    while i < 8 {
        cc_st32(state, (4 + i) * 4, cc_ld32(key, i * 4));
        i = i + 1;
    }
    cc_st32(state, 48, counter & 4294967295);
    i = 0;
    while i < 3 {
        cc_st32(state, (13 + i) * 4, cc_ld32(nonce, i * 4));
        i = i + 1;
    }
}
fn chacha_block(state: ptr, ks: ptr) {
    let work: [64] byte = 0;
    let i: i64 = 0;
    while i < 64 {
        store8(work + i, load8(state + i));
        i = i + 1;
    }
    chacha_rounds(work);
    chacha_rounds(work);
    chacha_rounds(work);
    chacha_rounds(work);
    chacha_rounds(work);
    chacha_rounds(work);
    chacha_rounds(work);
    chacha_rounds(work);
    chacha_rounds(work);
    chacha_rounds(work);
    i = 0;
    while i < 16 {
        cc_st32(ks, i * 4, (cc_ld32(work, i * 4) + cc_ld32(state, i * 4)) & 4294967295);
        i = i + 1;
    }
}
fn chacha20(key: ptr, nonce: ptr, data: ptr, out: ptr, mlen: i64) {
    let state: [64] byte = 0;
    let ks: [64] byte = 0;
    chacha_init_state(state, key, 1, nonce);
    let off: i64 = 0;
    while off < mlen {
        chacha_block(state, ks);
        let j: i64 = 0;
        while j < 64 {
            if off + j < mlen {
                store8(out + off + j, load8(data + off + j) ^ load8(ks + j));
            }
            j = j + 1;
        }
        off = off + 64;
        cc_st32(state, 48, (cc_ld32(state, 48) + 1) & 4294967295);
    }
}
