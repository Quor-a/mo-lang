import "sha512.mo";
import "sha256.mo";

# HMAC-SHA512（RFC 2104/RFC 4231）。
# SHA-512 block size = 128 字节：pad 128、K>128 才先 hash。
# 🔴 SHA-512 block size = 128 字节（非 64）：pad 128、K>128 才先 hash。
fn hmac_sha512(key: ptr, klen: i64, msg: ptr, mlen: i64, out: i64) -> i64 {
    let k: [128] byte = 0;
    if klen > 128 {
        sha512(key, klen, &k);
    } else {
        let i: i64 = 0;
        while i < klen {
            store8(&k + i, load8(key + i));
            i = i + 1;
        }
        while i < 128 {
            store8(&k + i, 0);
            i = i + 1;
        }
    }
    let inner: [512] byte = 0;
    let i2: i64 = 0;
    while i2 < 128 {
        store8(&inner + i2, (load8(&k + i2) ^ 0x36) & 255);
        i2 = i2 + 1;
    }
    i2 = 0;
    while i2 < mlen {
        store8(&inner + 128 + i2, load8(msg + i2));
        i2 = i2 + 1;
    }
    let ih: [64] byte = 0;
    sha512(&inner, 128 + mlen, &ih);
    let outer: [192] byte = 0;
    i2 = 0;
    while i2 < 128 {
        store8(&outer + i2, (load8(&k + i2) ^ 0x5c) & 255);
        i2 = i2 + 1;
    }
    i2 = 0;
    while i2 < 64 {
        store8(&outer + 128 + i2, load8(&ih + i2));
        i2 = i2 + 1;
    }
    sha512(&outer, 192, out);
    return 0;
}


# ===== HMAC-SHA256（RFC 4231；SHA-256 block=64）=====
fn hmac_sha256(key: ptr, klen: i64, msg: ptr, mlen: i64, out: i64) -> i64 {
    let k: [64] byte = 0;
    if klen > 64 {
        sha256(key, klen, &k);
    } else {
        let i: i64 = 0;
        while i < klen {
            store8(&k + i, load8(key + i));
            i = i + 1;
        }
        while i < 64 {
            store8(&k + i, 0);
            i = i + 1;
        }
    }
    let inner: [256] byte = 0;
    let i2: i64 = 0;
    while i2 < 64 {
        store8(&inner + i2, (load8(&k + i2) ^ 0x36) & 255);
        i2 = i2 + 1;
    }
    i2 = 0;
    while i2 < mlen {
        store8(&inner + 64 + i2, load8(msg + i2));
        i2 = i2 + 1;
    }
    let ih: [32] byte = 0;
    sha256(&inner, 64 + mlen, &ih);
    let outer: [96] byte = 0;
    i2 = 0;
    while i2 < 64 {
        store8(&outer + i2, (load8(&k + i2) ^ 0x5c) & 255);
        i2 = i2 + 1;
    }
    i2 = 0;
    while i2 < 32 {
        store8(&outer + 64 + i2, load8(&ih + i2));
        i2 = i2 + 1;
    }
    sha256(&outer, 96, out);
    return 0;
}

# 便捷：HMAC-SHA256 hex 输出（65 字节缓冲，含 NUL）
fn hmac_hex(key: ptr, klen: i64, msg: ptr, mlen: i64, out: i64) -> i64 {
    let d: [32] byte = 0;
    hmac_sha256(key, klen, msg, mlen, &d);
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

# 验证：重算 mac 与给定 hex 串比对（恒时比较防时序侧信道）
fn mac_verify(key: ptr, klen: i64, msg: ptr, mlen: i64, macthex: i64) -> i64 {
    let calc: [66] byte = 0;
    hmac_hex(key, klen, msg, mlen, &calc);
    let diff: i64 = 0;
    let i: i64 = 0;
    while i < 64 {
        diff = diff | ((calc[i] & 255) ^ (load8(macthex + i) & 255));
        i = i + 1;
    }
    if diff == 0 { return 1; }
    return 0;
}
