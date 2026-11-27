# SHA-256（FIPS 180-4）。i64 承载 32 位字（恒 &0xFFFFFFFF）。
# lshr=无符号除法；shl=乘法；mo 的 >> 是 sar 禁用。
fn s256_lshr(x: i64, n: i64) -> i64 {
    return (x & 0xFFFFFFFF) / (1 << n);
}

fn s256_shl(x: i64, n: i64) -> i64 {
    return ((x & 0xFFFFFFFF) * (1 << n)) & 0xFFFFFFFF;
}

fn s256_rotr(x: i64, n: i64) -> i64 {
    return (s256_lshr(x, n) | s256_shl(x, 32 - n)) & 0xFFFFFFFF;
}

var S256_K_READY: i64 = 0;
var S256_K: [64] i64 = 0;

fn s256_init_k() -> i64 {
    if S256_K_READY == 1 { return 0; }
    S256_K[0] = 0x428a2f98; S256_K[1] = 0x71374491; S256_K[2] = 0xb5c0fbcf; S256_K[3] = 0xe9b5dba5;
    S256_K[4] = 0x3956c25b; S256_K[5] = 0x59f111f1; S256_K[6] = 0x923f82a4; S256_K[7] = 0xab1c5ed5;
    S256_K[8] = 0xd807aa98; S256_K[9] = 0x12835b01; S256_K[10] = 0x243185be; S256_K[11] = 0x550c7dc3;
    S256_K[12] = 0x72be5d74; S256_K[13] = 0x80deb1fe; S256_K[14] = 0x9bdc06a7; S256_K[15] = 0xc19bf174;
    S256_K[16] = 0xe49b69c1; S256_K[17] = 0xefbe4786; S256_K[18] = 0x0fc19dc6; S256_K[19] = 0x240ca1cc;
    S256_K[20] = 0x2de92c6f; S256_K[21] = 0x4a7484aa; S256_K[22] = 0x5cb0a9dc; S256_K[23] = 0x76f988da;
    S256_K[24] = 0x983e5152; S256_K[25] = 0xa831c66d; S256_K[26] = 0xb00327c8; S256_K[27] = 0xbf597fc7;
    S256_K[28] = 0xc6e00bf3; S256_K[29] = 0xd5a79147; S256_K[30] = 0x06ca6351; S256_K[31] = 0x14292967;
    S256_K[32] = 0x27b70a85; S256_K[33] = 0x2e1b2138; S256_K[34] = 0x4d2c6dfc; S256_K[35] = 0x53380d13;
    S256_K[36] = 0x650a7354; S256_K[37] = 0x766a0abb; S256_K[38] = 0x81c2c92e; S256_K[39] = 0x92722c85;
    S256_K[40] = 0xa2bfe8a1; S256_K[41] = 0xa81a664b; S256_K[42] = 0xc24b8b70; S256_K[43] = 0xc76c51a3;
    S256_K[44] = 0xd192e819; S256_K[45] = 0xd6990624; S256_K[46] = 0xf40e3585; S256_K[47] = 0x106aa070;
    S256_K[48] = 0x19a4c116; S256_K[49] = 0x1e376c08; S256_K[50] = 0x2748774c; S256_K[51] = 0x34b0bcb5;
    S256_K[52] = 0x391c0cb3; S256_K[53] = 0x4ed8aa4a; S256_K[54] = 0x5b9cca4f; S256_K[55] = 0x682e6ff3;
    S256_K[56] = 0x748f82ee; S256_K[57] = 0x78a5636f; S256_K[58] = 0x84c87814; S256_K[59] = 0x8cc70208;
    S256_K[60] = 0x90befffa; S256_K[61] = 0xa4506ceb; S256_K[62] = 0xbef9a3f7; S256_K[63] = 0xc67178f2;
    S256_K_READY = 1;
    return 0;
}

fn sha256(msg: ptr, mlen: i64, out: i64) -> i64 {
    s256_init_k();
    let h0: i64 = 0x6a09e667; let h1: i64 = 0xbb67ae85;
    let h2: i64 = 0x3c6ef372; let h3: i64 = 0xa54ff53a;
    let h4: i64 = 0x510e527f; let h5: i64 = 0x9b05688c;
    let h6: i64 = 0x1f83d9ab; let h7: i64 = 0x5be0cd19;
    let total: i64 = mlen + 9;
    let nblocks: i64 = (total + 63) / 64;
    let buf: [256] byte = 0;
    let i: i64 = 0;
    while i < mlen {
        buf[i] = load8(msg + i) & 255;
        i = i + 1;
    }
    buf[mlen] = 0x80;
    let bits: i64 = mlen * 8;
    let lofs: i64 = nblocks * 64 - 8;
    i = 0;
    while i < 8 {
        buf[lofs + i] = s256_lshr(bits, 56 - i * 8) & 255;
        i = i + 1;
    }
    let bi: i64 = 0;
    while bi < nblocks {
        let w: [64] i64 = 0;
        i = 0;
        while i < 16 {
            let o: i64 = bi * 64 + i * 4;
            w[i] = (buf[o] & 255) * 16777216 + (buf[o + 1] & 255) * 65536 + (buf[o + 2] & 255) * 256 + (buf[o + 3] & 255);
            i = i + 1;
        }
        i = 16;
        while i < 64 {
            let s0: i64 = s256_rotr(w[i - 15], 7) ^ s256_rotr(w[i - 15], 18) ^ s256_lshr(w[i - 15], 3);
            let s1: i64 = s256_rotr(w[i - 2], 17) ^ s256_rotr(w[i - 2], 19) ^ s256_lshr(w[i - 2], 10);
            w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & 0xFFFFFFFF;
            i = i + 1;
        }
        let a: i64 = h0; let b: i64 = h1; let c: i64 = h2; let d: i64 = h3;
        let e: i64 = h4; let f: i64 = h5; let g: i64 = h6; let hh: i64 = h7;
        let j: i64 = 0;
        while j < 64 {
            let S1: i64 = s256_rotr(e, 6) ^ s256_rotr(e, 11) ^ s256_rotr(e, 25);
            let ch: i64 = (e & f) ^ ((e ^ 0xFFFFFFFF) & g);
            let t1: i64 = (hh + S1 + ch + S256_K[j] + w[j]) & 0xFFFFFFFF;
            let S0: i64 = s256_rotr(a, 2) ^ s256_rotr(a, 13) ^ s256_rotr(a, 22);
            let maj: i64 = (a & b) ^ (a & c) ^ (b & c);
            let t2: i64 = (S0 + maj) & 0xFFFFFFFF;
            hh = g; g = f; f = e;
            e = (d + t1) & 0xFFFFFFFF;
            d = c; c = b; b = a;
            a = (t1 + t2) & 0xFFFFFFFF;
            j = j + 1;
        }
        h0 = (h0 + a) & 0xFFFFFFFF; h1 = (h1 + b) & 0xFFFFFFFF;
        h2 = (h2 + c) & 0xFFFFFFFF; h3 = (h3 + d) & 0xFFFFFFFF;
        h4 = (h4 + e) & 0xFFFFFFFF; h5 = (h5 + f) & 0xFFFFFFFF;
        h6 = (h6 + g) & 0xFFFFFFFF; h7 = (h7 + hh) & 0xFFFFFFFF;
        bi = bi + 1;
    }
    i = 0;
    while i < 8 {
        let hv: i64 = 0;
        if i == 0 { hv = h0; }
        if i == 1 { hv = h1; }
        if i == 2 { hv = h2; }
        if i == 3 { hv = h3; }
        if i == 4 { hv = h4; }
        if i == 5 { hv = h5; }
        if i == 6 { hv = h6; }
        if i == 7 { hv = h7; }
        store8(out + i * 4 + 0, s256_lshr(hv, 24) & 255);
        store8(out + i * 4 + 1, (hv >> 16) & 255);
        store8(out + i * 4 + 2, (hv >> 8) & 255);
        store8(out + i * 4 + 3, hv & 255);
        i = i + 1;
    }
    return 0;
}

fn sha256_hex(msg: ptr, mlen: i64, out: i64) -> i64 {
    let d: [32] byte = 0;
    sha256(msg, mlen, &d);
    let D: ptr = "0123456789abcdef";
    let i: i64 = 0;
    while i < 32 {
        let v: i64 = d[i] & 255;
        store8(out + i * 2, load8(D + (v >> 4)));
        store8(out + i * 2 + 1, load8(D + (v & 15)));
        i = i + 1;
    }
    store8(out + 64, 0);
    return 0;
}
