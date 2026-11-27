# HKDF（RFC 5869），SHA-256 版。L<=255*32 字节。
import "hmac.mo";

fn hkdf_sha256_extract(salt: ptr, slen: i64, ikm: ptr, ilen: i64, prk: i64) -> i64 {
    # PRK = HMAC-SHA256(salt, IKM)；salt 空时=hashlen 个 0
    let zeros: [32] byte = 0;
    if slen == 0 {
        hmac_sha256(&zeros, 32, ikm, ilen, prk);
    } else {
        hmac_sha256(salt, slen, ikm, ilen, prk);
    }
    return 0;
}

fn hkdf_sha256_expand(prk: i64, info: ptr, ilen: i64, out: i64, l: i64) -> i64 {
    if l > 8160 { return -1; }
    let n: i64 = (l + 31) / 32;
    let t: [32] byte = 0;
    let tlen: i64 = 0;
    let ctr: i64 = 1;
    let done: i64 = 0;
    while ctr <= n {
        # 输入 = T(ctr-1) || info || ctr(1B)
        let buf: [288] byte = 0;
        let i: i64 = 0;
        while i < tlen {
            buf[i] = t[i];
            i = i + 1;
        }
        i = 0;
        while i < ilen {
            buf[tlen + i] = load8(info + i);
            i = i + 1;
        }
        buf[tlen + ilen] = ctr & 255;
        let o: [32] byte = 0;
        hmac_sha256(prk, 32, &buf, tlen + ilen + 1, &o);
        let take: i64 = 32;
        if l - done < 32 { take = l - done; }
        i = 0;
        while i < take {
            store8(out + done + i, o[i]);
            i = i + 1;
        }
        done = done + take;
        # t = o
        i = 0;
        while i < 32 {
            t[i] = o[i];
            i = i + 1;
        }
        tlen = 32;
        ctr = ctr + 1;
    }
    return 0;
}

fn hkdf_sha256(salt: ptr, slen: i64, ikm: ptr, ilen: i64, info: ptr, ilen2: i64, out: i64, l: i64) -> i64 {
    let prk: [32] byte = 0;
    hkdf_sha256_extract(salt, slen, ikm, ilen, &prk);
    hkdf_sha256_expand(&prk, info, ilen2, out, l);
    return 0;
}
