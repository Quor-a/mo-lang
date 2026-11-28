# poly1305 (RFC 8439) - built on big.mo (handles are i64)
import "big.mo";
import "mem.mo";
# build big integer from little-endian byte buffer
fn poly_big_from_le(p: ptr, n: i64) -> i64 {
    let acc: i64 = big_from_i64(0);
    let base: i64 = big_from_i64(256);
    let i: i64 = n - 1;
    while i >= 0 {
        acc = big_mul_small(acc, 256);
        acc = big_add(acc, big_from_i64(load8(p + i)));
        i = i - 1;
    }
    return acc;
}
fn poly1305(key: ptr, msg: ptr, mlen: i64, tag: ptr) {
    heap_init();
    # P = 2^130 - 5
    let p130: i64 = big_from_i64(1);
    let k: i64 = 0;
    while k < 130 {
        p130 = big_mul_small(p130, 2);
        k = k + 1;
    }
    let P: i64 = big_sub(p130, big_from_i64(5));
    # clamped r
    let rb: [16] byte = 0;
    let i: i64 = 0;
    while i < 16 {
        store8(rb + i, load8(key + i));
        i = i + 1;
    }
    store8(rb + 3, load8(rb + 3) & 15);
    store8(rb + 7, load8(rb + 7) & 15);
    store8(rb + 11, load8(rb + 11) & 15);
    store8(rb + 15, load8(rb + 15) & 15);
    store8(rb + 4, load8(rb + 4) & 252);
    store8(rb + 8, load8(rb + 8) & 252);
    store8(rb + 12, load8(rb + 12) & 252);
    let rnum: i64 = poly_big_from_le(rb, 16);
    let acc: i64 = big_from_i64(0);
    i = 0;
    while i < mlen {
        let n: i64 = 16;
        if mlen - i < 16 { n = mlen - i; }
        let blk: [17] byte = 0;
        let j: i64 = 0;
        while j < n {
            store8(blk + j, load8(msg + i + j));
            j = j + 1;
        }
        store8(blk + n, 1);
        let bnum: i64 = poly_big_from_le(blk, n + 1);
        acc = big_add(acc, bnum);
        acc = big_mod(big_mul(acc, rnum), P);
        i = i + 16;
    }
    let sb: [16] byte = 0;
    i = 0;
    while i < 16 {
        store8(sb + i, load8(key + 16 + i));
        i = i + 1;
    }
    acc = big_add(acc, poly_big_from_le(sb, 16));
    # serialize LE 16B: acc < 2^130ish < 2^144? acc=s+acc<2^131 <2^136 → 17B buffer
    # serialize: repeated divmod by 256 (RADIX is 10^4 decimal, limbs are not bytes)
    let q256: i64 = big_from_i64(256);
    i = 0;
    while i < 16 {
        let qt: i64 = big_divmod(acc, q256);
        store8(tag + i, big_limb(BIG_REM, 0));
        acc = qt;
        i = i + 1;
    }
}
