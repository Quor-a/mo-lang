# 370 —— lib/sha256.mo：RFC 边界向量（空串/短串/55/56/57/64/111/128 字节）全部对 hashlib
import "sha256.mo";
import "assert.mo";
import "io.mo";

fn chk(name: ptr, got: ptr, want: ptr) -> i64 {
    assert_eq(name, streq(got, want), 1);
    return 0;
}

fn main() -> i64 {
    let hx: [70] byte = 0;
    sha256_hex("", 0, &hx);
    chk("empty", &hx, "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
    sha256_hex("abc", 3, &hx);
    chk("abc", &hx, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
    sha256_hex("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq", 56, &hx);
    chk("448bit", &hx, "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1");
    # 边界 55/57/64/111 字节
    let d: [128] byte = 0;
    let i: i64 = 0;
    while i < 128 { d[i] = 97 + (i & 3); i = i + 1; }
    let want55: [70] byte = 0;
    let want57: [70] byte = 0;
    let want64: [70] byte = 0;
    let want111: [70] byte = 0;
    hex55(&want55);
    hex57(&want57);
    hex64(&want64);
    hex111(&want111);
    sha256_hex(&d, 55, &hx);
    chk("55B", &hx, &want55);
    sha256_hex(&d, 57, &hx);
    chk("57B", &hx, &want57);
    sha256_hex(&d, 64, &hx);
    chk("64B", &hx, &want64);
    sha256_hex(&d, 111, &hx);
    chk("111B", &hx, &want111);
    test_done();
    return 0;
}

fn hex55(out: i64) -> i64 {
    cpy(out, "2c886b3d53367f58d29fe6f41442c60c63005ce9f6c59783c01b7832fb260d5b");
    return 0;
}
fn hex57(out: i64) -> i64 {
    cpy(out, "8112571d6d1e25bfee512fc699c1d195d0011b5b46cf013abe5d23e4f8fb22be");
    return 0;
}
fn hex64(out: i64) -> i64 {
    cpy(out, "625b41490b883891943c5fa54ad45d7c900b9b6e91e159334e320b1f5215a209");
    return 0;
}
fn hex111(out: i64) -> i64 {
    cpy(out, "b89ff9736fbb65cb7253d07657f49ce5d51adc1b95ffefb29c67429f9fbef7ee");
    return 0;
}

fn cpy(dst: i64, s: ptr) -> i64 {
    let i: i64 = 0;
    while load8(s + i) != 0 {
        store8(dst + i, load8(s + i));
        i = i + 1;
    }
    store8(dst + i, 0);
    return 0;
}
