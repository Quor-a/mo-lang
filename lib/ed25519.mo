# lib/ed25519.mo — Ed25519（RFC 8032）：域算术 + 点运算 + 签名/公钥/验证
# 基于通用大数 lib/big.mo（正确性优先）。SHA-512 依赖 lib/sha512.mo。
# 域 p = 2^255-19，群阶 l = 2^252 + 27742317777372353535851937790883648493。
# 注意：mo 的 >> 是 sar。lshr = (x >> n) & mask 由调用方保证（本库标量路径用 big）。
import "mem.mo";
import "big.mo";
import "sha512.mo";
import "str.mo";

# ===== 域常量 =====
var FE_P: i64 = 0;
var FE_TWO: i64 = 0;
var FE_INIT: i64 = 0;

fn fe_init() -> i64 {
    if FE_INIT == 1 { return 0; }
    if heap_ready() == 0 { heap_init(); }
    FE_P = big_from_str("57896044618658097711785492504343953926634992332820282019728792003956564819949");
    FE_TWO = big_from_i64(2);
    FE_INIT = 1;
    return 0;
}

fn fe_red(a: i64) -> i64 {
    return big_mod(a, FE_P);
}

fn fe_from_i64(v: i64) -> i64 {
    if v < 0 {
        let b: i64 = big_from_i64(0 - v);
        return big_sub(FE_P, b);
    }
    return big_from_i64(v);
}

fn fe_add(a: i64, b: i64) -> i64 {
    let s: i64 = big_add(a, b);
    let c: i64 = big_cmp(s, FE_P);
    if c >= 0 { s = big_sub(s, FE_P); }
    return s;
}

fn fe_sub(a: i64, b: i64) -> i64 {
    let c: i64 = big_cmp(a, b);
    if c < 0 {
        let t: i64 = big_sub(b, a);
        return big_sub(FE_P, t);
    }
    return big_sub(a, b);
}

fn fe_mul(a: i64, b: i64) -> i64 {
    return big_mod(big_mul(a, b), FE_P);
}

fn fe_sqr(a: i64) -> i64 {
    return fe_mul(a, a);
}

var FE_EXP: i64 = 0;

fn fe_inv(a: i64) -> i64 {
    if FE_EXP == 0 {
        let two: i64 = big_from_i64(2);
        FE_EXP = big_sub(FE_P, two);
    }
    return fe_pow(a, FE_EXP);
}

fn fe_pow(base: i64, e: i64) -> i64 {
    let bits: [512] byte = 0;
    let n: i64 = 0;
    let t: i64 = e;
    while big_is_zero(t) == 0 {
        let q: i64 = big_divmod(t, FE_TWO);
        let rem: i64 = big_sub(t, big_mul(FE_TWO, q));
        bits[n] = fe_is_one(rem);
        n = n + 1;
        t = q;
    }
    let r: i64 = big_from_i64(1);
    let i: i64 = n - 1;
    while i >= 0 {
        r = fe_sqr(r);
        if bits[i] == 1 { r = fe_mul(r, base); }
        i = i - 1;
    }
    return r;
}

fn fe_is_one(a: i64) -> i64 {
    let one: i64 = big_from_i64(1);
    return big_eq(a, one);
}

fn fe_is_zero(a: i64) -> i64 {
    return big_is_zero(a);
}

fn fe_eq(a: i64, b: i64) -> i64 {
    return big_eq(a, b);
}

fn fe_neg(a: i64) -> i64 {
    if fe_is_zero(a) == 1 { return a; }
    return big_sub(FE_P, a);
}

fn fe_from_bytes(b: i64) -> i64 {
    let acc: i64 = big_from_i64(0);
    let B256: i64 = big_from_i64(256);
    let i: i64 = 31;
    while i >= 0 {
        acc = big_add(big_mul(acc, B256), big_from_i64(load8(b + i) & 255));
        i = i - 1;
    }
    return fe_red(acc);
}

fn fe_to_bytes(a: i64, out: i64) -> i64 {
    let t: i64 = a;
    let B256: i64 = big_from_i64(256);
    let i: i64 = 0;
    while i < 32 {
        let q: i64 = big_divmod(t, B256);
        let rem: i64 = big_sub(t, big_mul(B256, q));
        store8(out + i, fe_low_byte(rem));
        t = q;
        i = i + 1;
    }
    return 0;
}

fn fe_low_byte(a: i64) -> i64 {
    let buf: [80] byte = 0;
    big_to_str(a, &buf);
    return atoi(&buf);
}

# ===== 点运算（extended coordinates X,Y,Z,T）=====
var ED_BX: i64 = 0;
var ED_BY: i64 = 0;
var ED_D: i64 = 0;
var ED_ZERO: i64 = 0;
var ED_ONE: i64 = 0;
var ED_INIT2: i64 = 0;
var ED_L: i64 = 0;

fn ed_init() -> i64 {
    if ED_INIT2 == 1 { return 0; }
    fe_init();
    ED_BX = big_from_str("15112221349535400772501151409588531511454012693041857206046113283949847762202");
    ED_BY = big_from_str("46316835694926478169428394003475163141307993866256225615783033603165251855960");
    ED_D = fe_mul(fe_from_i64(0 - 121665), fe_inv(fe_from_i64(121666)));
    ED_ZERO = big_from_i64(0);
    ED_ONE = big_from_i64(1);
    ED_INIT2 = 1;
    return 0;
}

fn ed_alloc() -> i64 {
    return alloc(40);
}

fn ed_set(p: i64, x: i64, y: i64, z: i64, t: i64) -> i64 {
    store64(p, x);
    store64(p + 8, y);
    store64(p + 16, z);
    store64(p + 24, t);
    store64(p + 32, fe_add(x, y));
    return 0;
}

fn ed_identity(p: i64) -> i64 {
    ed_set(p, ED_ZERO, ED_ONE, ED_ONE, ED_ZERO);
    return 0;
}

fn ed_base(p: i64) -> i64 {
    ed_set(p, ED_BX, ED_BY, ED_ONE, fe_mul(ED_BX, ED_BY));
    return 0;
}

var ED_D2: i64 = 0;

fn ed_add(p3: i64, p1: i64, p2: i64) -> i64 {
    if ED_D2 == 0 { ED_D2 = fe_add(ED_D, ED_D); }
    let x1: i64 = load64(p1);
    let y1: i64 = load64(p1 + 8);
    let z1: i64 = load64(p1 + 16);
    let t1: i64 = load64(p1 + 24);
    let x2: i64 = load64(p2);
    let y2: i64 = load64(p2 + 8);
    let z2: i64 = load64(p2 + 16);
    let t2: i64 = load64(p2 + 24);
    let a: i64 = fe_mul(fe_sub(y1, x1), fe_sub(y2, x2));
    let b: i64 = fe_mul(fe_add(y1, x1), fe_add(y2, x2));
    let c: i64 = fe_mul(t1, fe_mul(ED_D2, t2));
    let d: i64 = fe_mul(z1, fe_add(z2, z2));
    let e: i64 = fe_sub(b, a);
    let f: i64 = fe_sub(d, c);
    let g: i64 = fe_add(d, c);
    let h: i64 = fe_add(b, a);
    ed_set(p3, fe_mul(e, f), fe_mul(g, h), fe_mul(f, g), fe_mul(e, h));
    return 0;
}

fn ed_scalarmult(out: i64, k: i64, p: i64) -> i64 {
    let bits: [512] byte = 0;
    let B256: i64 = big_from_i64(256);
    let t: i64 = k;
    let n: i64 = 0;
    while big_is_zero(t) == 0 {
        let q: i64 = big_divmod(t, B256);
        let rem: i64 = big_sub(t, big_mul(B256, q));
        let lb: i64 = fe_low_byte(rem);
        let j: i64 = 0;
        while j < 8 {
            bits[n * 8 + j] = (lb >> j) & 1;
            j = j + 1;
        }
        n = n + 1;
        t = q;
    }
    let r: i64 = ed_alloc();
    ed_identity(r);
    let acc: i64 = ed_alloc();
    ed_set(acc, load64(p), load64(p + 8), load64(p + 16), load64(p + 24));
    let tmp: i64 = ed_alloc();
    let i: i64 = n * 8 - 1;
    while i >= 0 {
        ed_add(tmp, r, r);
        ed_set(r, load64(tmp), load64(tmp + 8), load64(tmp + 16), load64(tmp + 24));
        if bits[i] == 1 {
            ed_add(tmp, r, acc);
            ed_set(r, load64(tmp), load64(tmp + 8), load64(tmp + 16), load64(tmp + 24));
        }
        i = i - 1;
    }
    ed_set(out, load64(r), load64(r + 8), load64(r + 16), load64(r + 24));
    return 0;
}

fn ed_encode(p: i64, out: i64) -> i64 {
    let zinv: i64 = fe_inv(load64(p + 16));
    let x: i64 = fe_mul(load64(p), zinv);
    let y: i64 = fe_mul(load64(p + 8), zinv);
    fe_to_bytes(y, out);
    let xb2: [32] byte = 0;
    fe_to_bytes(x, &xb2);
    let parity: i64 = xb2[0] & 1;
    store8(out + 31, (load8(out + 31) & 127) | (parity << 7));
    return 0;
}

# ===== 标量辅助 =====
fn ed_scalar_from_bytes_n(b: i64, nb: i64) -> i64 {
    let acc: i64 = big_from_i64(0);
    let B256: i64 = big_from_i64(256);
    let i: i64 = nb - 1;
    while i >= 0 {
        acc = big_add(big_mul(acc, B256), big_from_i64(load8(b + i) & 255));
        i = i - 1;
    }
    return acc;
}

fn ed_scalar_from_bytes(b: i64) -> i64 {
    return ed_scalar_from_bytes_n(b, 32);
}

fn ed_mod_l(a: i64) -> i64 {
    if ED_L == 0 { ED_L = big_from_str("7237005577332262213973186563042994240857116359379907606001950938285454250989"); }
    return big_mod(a, ED_L);
}

fn ed_clamp(h: i64, out: i64) -> i64 {
    let i: i64 = 0;
    while i < 32 {
        store8(out + i, load8(h + i));
        i = i + 1;
    }
    store8(out, load8(out) & 248);
    store8(out + 31, (load8(out + 31) & 127) | 64);
    return 0;
}

# ===== 公钥 =====
fn ed_pubkey(sk: i64, pk: i64) -> i64 {
    let h: [64] byte = 0;
    sha512(sk, 32, &h);
    let a: [32] byte = 0;
    ed_clamp(&h, &a);
    let av: i64 = ed_scalar_from_bytes(&a);
    let b: i64 = ed_alloc();
    ed_base(b);
    let A: i64 = ed_alloc();
    ed_scalarmult(A, av, b);
    ed_encode(A, pk);
    return 0;
}

# ===== 签名 =====
fn ed_sign(sk: i64, msg: i64, mlen: i64, sig: i64) -> i64 {
    let h: [64] byte = 0;
    sha512(sk, 32, &h);
    let a: [32] byte = 0;
    ed_clamp(&h, &a);
    let av: i64 = ed_scalar_from_bytes(&a);
    let b: i64 = ed_alloc();
    ed_base(b);
    let A: i64 = ed_alloc();
    ed_scalarmult(A, av, b);
    let pk: [32] byte = 0;
    ed_encode(A, &pk);
    let rb: [128] byte = 0;
    let i: i64 = 0;
    while i < 32 {
        store8(&rb + i, h[32 + i]);
        i = i + 1;
    }
    i = 0;
    while i < mlen {
        store8(&rb + 32 + i, load8(msg + i));
        i = i + 1;
    }
    let hr: [64] byte = 0;
    sha512(&rb, 32 + mlen, &hr);
    let rv: i64 = ed_mod_l(ed_scalar_from_bytes_n(&hr, 64));
    let R: i64 = ed_alloc();
    ed_scalarmult(R, rv, b);
    ed_encode(R, sig);
    let kb: [160] byte = 0;
    i = 0;
    while i < 32 {
        store8(&kb + i, load8(sig + i));
        store8(&kb + 32 + i, pk[i]);
        i = i + 1;
    }
    i = 0;
    while i < mlen {
        store8(&kb + 64 + i, load8(msg + i));
        i = i + 1;
    }
    let hk: [64] byte = 0;
    sha512(&kb, 64 + mlen, &hk);
    let kv: i64 = ed_mod_l(ed_scalar_from_bytes_n(&hk, 64));
    let ka: i64 = ed_mod_l(big_mul(kv, av));
    let sv: i64 = ed_mod_l(big_add(rv, ka));
    fe_to_bytes(sv, sig + 32);
    return 0;
}


# ===== 验证 =====
var ED_SQRTM1: i64 = 0;
var ED_POW_K: i64 = 0;

fn ed_decode(pk: i64) -> i64 {
    let yb: [32] byte = 0;
    let i: i64 = 0;
    while i < 32 {
        yb[i] = load8(pk + i);
        i = i + 1;
    }
    let sign: i64 = (yb[31] >> 7) & 1;
    store8(&yb + 31, yb[31] & 127);
    let y: i64 = ed_scalar_from_bytes(&yb);
    let one: i64 = big_from_i64(1);
    let u: i64 = fe_sub(fe_sqr(y), one);
    let v: i64 = fe_add(fe_mul(ED_D, fe_sqr(y)), one);
    if ED_POW_K == 0 {
        ED_POW_K = big_divmod(big_sub(FE_P, big_from_i64(5)), big_from_i64(8));
        ED_SQRTM1 = fe_pow(big_from_i64(2), big_divmod(big_sub(FE_P, big_from_i64(1)), big_from_i64(4)));
    }
    let v3: i64 = fe_mul(v, fe_mul(v, v));
    let uv7: i64 = fe_mul(u, fe_mul(v3, fe_mul(v, fe_mul(v, fe_mul(v, v)))));
    let x: i64 = fe_mul(u, fe_mul(v3, fe_pow(uv7, ED_POW_K)));
    let vx2: i64 = fe_mul(v, fe_sqr(x));
    if fe_eq(vx2, u) == 0 {
        if fe_eq(vx2, fe_neg(u)) == 1 {
            x = fe_mul(x, ED_SQRTM1);
        } else {
            return 0;
        }
    }
    let xb: [32] byte = 0;
    fe_to_bytes(x, &xb);
    let parity: i64 = xb[0] & 1;
    if parity != sign { x = fe_neg(x); }
    let t: i64 = fe_mul(x, y);
    let p: i64 = ed_alloc();
    ed_set(p, x, y, big_from_i64(1), t);
    return p;
}

fn ed_verify(pk: i64, msg: i64, mlen: i64, sig: i64) -> i64 {
    let sbytes: [32] byte = 0;
    let i: i64 = 0;
    while i < 32 {
        sbytes[i] = load8(sig + 32 + i);
        i = i + 1;
    }
    let sv: i64 = ed_scalar_from_bytes(&sbytes);
    if ED_L == 0 { ED_L = big_from_str("7237005577332262213973186563042994240857116359379907606001950938285454250989"); }
    if big_cmp(sv, ED_L) >= 0 { return 0; }
    let A: i64 = ed_decode(pk);
    if A == 0 { return 0; }
    let kb: [160] byte = 0;
    i = 0;
    while i < 32 {
        store8(&kb + i, load8(sig + i));
        store8(&kb + 32 + i, load8(pk + i));
        i = i + 1;
    }
    i = 0;
    while i < mlen {
        store8(&kb + 64 + i, load8(msg + i));
        i = i + 1;
    }
    let hk: [64] byte = 0;
    sha512(&kb, 64 + mlen, &hk);
    let kv: i64 = ed_mod_l(ed_scalar_from_bytes_n(&hk, 64));
    let b: i64 = ed_alloc();
    ed_base(b);
    let SB: i64 = ed_alloc();
    ed_scalarmult(SB, sv, b);
    let kA: i64 = ed_alloc();
    ed_scalarmult(kA, kv, A);
    # -kA: 负点
    let nkA: i64 = ed_alloc();
    ed_set(nkA, fe_neg(load64(kA)), load64(kA + 8), load64(kA + 16), fe_neg(load64(kA + 24)));
    let sum: i64 = ed_alloc();
    ed_add(sum, SB, nkA);
    let enc: [32] byte = 0;
    ed_encode(sum, &enc);
    i = 0;
    while i < 32 {
        if (enc[i] & 255) != (load8(sig + i) & 255) { return 0; }
        i = i + 1;
    }
    return 1;
}
