# lib/sha512.mo — SHA-512 (FIPS 180-4)
# >>> 是逻辑右移需求：mo 的 >> = sar。lshr(x,n) 内联实现（变量承载 mask）。
import "mem.mo";

var K: [80] i64 = [
0x428a2f98d728ae22,0x7137449123ef65cd,0xb5c0fbcfec4d3b2f,0xe9b5dba58189dbbc,
0x3956c25bf348b538,0x59f111f1b605d019,0x923f82a4af194f9b,0xab1c5ed5da6d8118,
0xd807aa98a3030242,0x12835b0145706fbe,0x243185be4ee4b28c,0x550c7dc3d5ffb4e2,
0x72be5d74f27b896f,0x80deb1fe3b1696b1,0x9bdc06a725c71235,0xc19bf174cf692694,
0xe49b69c19ef14ad2,0xefbe4786384f25e3,0x0fc19dc68b8cd5b5,0x240ca1cc77ac9c65,
0x2de92c6f592b0275,0x4a7484aa6ea6e483,0x5cb0a9dcbd41fbd4,0x76f988da831153b5,
0x983e5152ee66dfab,0xa831c66d2db43210,0xb00327c898fb213f,0xbf597fc7beef0ee4,
0xc6e00bf33da88fc2,0xd5a79147930aa725,0x06ca6351e003826f,0x142929670a0e6e70,
0x27b70a8546d22ffc,0x2e1b21385c26c926,0x4d2c6dfc5ac42aed,0x53380d139d95b3df,
0x650a73548baf63de,0x766a0abb3c77b2a8,0x81c2c92e47edaee6,0x92722c851482353b,
0xa2bfe8a14cf10364,0xa81a664bbc423001,0xc24b8b70d0f89791,0xc76c51a30654be30,
0xd192e819d6ef5218,0xd69906245565a910,0xf40e35855771202a,0x106aa07032bbd1b8,
0x19a4c116b8d2d0c8,0x1e376c085141ab53,0x2748774cdf8eeb99,0x34b0bcb5e19b48a8,
0x391c0cb3c5c95a63,0x4ed8aa4ae3418acb,0x5b9cca4f7763e373,0x682e6ff3d6b2b8a3,
0x748f82ee5defb2fc,0x78a5636f43172f60,0x84c87814a1f0ab72,0x8cc702081a6439ec,
0x90befffa23631e28,0xa4506cebde82bde9,0xbef9a3f7b2c67915,0xc67178f2e372532b,
0xca273eceea26619c,0xd186b8c721c0c207,0xeada7dd6cde0eb1e,0xf57d4f7fee6ed178,
0x06f067aa72176fba,0x0a637dc5a2c898a6,0x113f9804bef90dae,0x1b710b35131c471b,
0x28db77f523047d84,0x32caab7b40c72493,0x3c9ebe0a15c9bebc,0x431d67c49c100d4c,
0x4cc5d4becb3e42b6,0x597f299cfc657e2a,0x5fcb6fab3ad6faec,0x6c44198c4a475817
];

# 逻辑右移（sar + mask）
fn lshr(x: i64, n: i64) -> i64 {
    if n == 0 { return x; }
    let one: i64 = 1;
    return (x >> n) & ((one << (64 - n)) - 1);
}

# 循环右移
fn rotr(x: i64, n: i64) -> i64 {
    return lshr(x, n) | (x << (64 - n));
}

fn bigend(p: i64) -> i64 {
    return (load8(p) << 56) | (load8(p+1) << 48) | (load8(p+2) << 40) | (load8(p+3) << 32)
         | (load8(p+4) << 24) | (load8(p+5) << 16) | (load8(p+6) << 8) | load8(p+7);
}

fn putbe(p: i64, v: i64) -> i64 {
    store8(p, lshr(v, 56) & 255);
    store8(p+1, lshr(v, 48) & 255);
    store8(p+2, lshr(v, 40) & 255);
    store8(p+3, lshr(v, 32) & 255);
    store8(p+4, lshr(v, 24) & 255);
    store8(p+5, lshr(v, 16) & 255);
    store8(p+6, lshr(v, 8) & 255);
    store8(p+7, v & 255);
    return 0;
}

# 初始 hash 值（8 个全局）
var H0: i64 = 0x6a09e667f3bcc908;
var H1: i64 = 0xbb67ae8584caa73b;
var H2: i64 = 0x3c6ef372fe94f82b;
var H3: i64 = 0xa54ff53a5f1d36f1;
var H4: i64 = 0x510e527fade682d1;
var H5: i64 = 0x9b05688c2b3e6c1f;
var H6: i64 = 0x1f83d9abfb41bd6b;
var H7: i64 = 0x5be0cd19137e2179;

var S512_W: [80] i64 = 0;

fn sha512_block(p: i64) -> i64 {
    let i: i64 = 0;
    while i < 16 {
        S512_W[i] = bigend(p + i * 8);
        i = i + 1;
    }
    while i < 80 {
        let s0: i64 = rotr(S512_W[i-15], 1) ^ rotr(S512_W[i-15], 8) ^ lshr(S512_W[i-15], 7);
        let s1: i64 = rotr(S512_W[i-2], 19) ^ rotr(S512_W[i-2], 61) ^ lshr(S512_W[i-2], 6);
        S512_W[i] = S512_W[i-16] + s0 + S512_W[i-7] + s1;
        i = i + 1;
    }
    let a: i64 = H0; let b: i64 = H1; let c: i64 = H2; let d: i64 = H3;
    let e: i64 = H4; let f: i64 = H5; let g: i64 = H6; let h: i64 = H7;
    let t: i64 = 0;
    while t < 80 {
        let S1: i64 = rotr(e, 14) ^ rotr(e, 18) ^ rotr(e, 41);
        let ch: i64 = (e & f) ^ ((~e) & g);
        let temp1: i64 = h + S1 + ch + K[t] + S512_W[t];
        let S0: i64 = rotr(a, 28) ^ rotr(a, 34) ^ rotr(a, 39);
        let maj: i64 = (a & b) ^ (a & c) ^ (b & c);
        let temp2: i64 = S0 + maj;
        h = g; g = f; f = e; e = d + temp1;
        d = c; c = b; b = a; a = temp1 + temp2;
        t = t + 1;
    }
    H0 = H0 + a; H1 = H1 + b; H2 = H2 + c; H3 = H3 + d;
    H4 = H4 + e; H5 = H5 + f; H6 = H6 + g; H7 = H7 + h;
    return 0;
}

# sha512(msg, len, out)：out 64 字节原始
fn sha512(msg: i64, n: i64, out: i64) -> i64 {
    H0 = 0x6a09e667f3bcc908; H1 = 0xbb67ae8584caa73b;
    H2 = 0x3c6ef372fe94f82b; H3 = 0xa54ff53a5f1d36f1;
    H4 = 0x510e527fade682d1; H5 = 0x9b05688c2b3e6c1f;
    H6 = 0x1f83d9abfb41bd6b; H7 = 0x5be0cd19137e2179;
    let blk: i64 = n / 128;
    let i: i64 = 0;
    while i < blk {
        sha512_block(msg + i * 128);
        i = i + 1;
    }
    # 尾部 padding（最长 2 块）
    let tail: [256] byte = 0;
    let rem: i64 = n - blk * 128;
    let ci: i64 = 0;
    while ci < rem {
        tail[ci] = load8(msg + blk * 128 + ci);
        ci = ci + 1;
    }
    tail[rem] = 128;
    let bitlen: i64 = n * 8;
    if rem + 9 <= 128 {
        putbe(&tail + 120, bitlen);
        sha512_block(&tail);
    } else {
        putbe(&tail + 248, bitlen);
        sha512_block(&tail);
        sha512_block(&tail + 128);
    }
    putbe(out, H0); putbe(out+8, H1); putbe(out+16, H2); putbe(out+24, H3);
    putbe(out+32, H4); putbe(out+40, H5); putbe(out+48, H6); putbe(out+56, H7);
    return 0;
}

fn hexd(v: i64, dst: i64) -> i64 {
    let D: ptr = "0123456789abcdef";
    let i: i64 = 0;
    while i < 2 {
        let d: i64 = lshr(v, (1 - i) * 4) & 15;
        store8(dst + i, load8(D + d));
        i = i + 1;
    }
    return 0;
}

# sha512_hex(msg, len, dst)：dst 至少 129 字节
fn sha512_hex(msg: i64, n: i64, dst: i64) -> i64 {
    let d: [64] byte = 0;
    sha512(msg, n, &d);
    let i: i64 = 0;
    while i < 64 {
        hexd(d[i], dst + i * 2);
        i = i + 1;
    }
    store8(dst + 128, 0);
    return 0;
}
