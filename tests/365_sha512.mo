# 365 —— lib/sha512.mo：SHA-512 四向量（空串 / abc / 双块 68B / 跨界 81B）
import "sha512.mo";
import "assert.mo";
import "str.mo";

fn chk(name: ptr, got: ptr, want: ptr) -> i64 {
    let ok: i64 = streq(got, want);
    assert_true(name, ok);
    return 0;
}

fn main() -> i64 {
    let out: [130] byte = 0;
    let emp: ptr = "";
    sha512_hex(emp, 0, &out);
    chk("empty", &out, "cf83e1357eefb8bdf1542850d66d8007d620e4050b5715dc83f4a921d36ce9ce47d0d13c5d85f2b0ff8318d2877eec2f63b931bd47417a81a538327af927da3e");
    sha512_hex("abc", 3, &out);
    chk("abc", &out, "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f");
    sha512_hex("abcdefghbcdefghijabcdefghbcdefghijabcdefghbcdefghijabcdefghbcdefghij", 68, &out);
    chk("two-block", &out, "ead62005e77fcbbc83536c8ba7fc818c78a116f7e0d235d5b404f8b6595306a36fc3fd90c51e25d1767ca629527cb6d6abe9a0b57774013cafd0b6cb61d3d0eb");
    sha512_hex("abcdefghbcdefghijabcdefghbcdefghijabcdefghbcdefghijabcdefghbcdefghijabcdefghbcdef", 81, &out);
    chk("cross-boundary", &out, "d90747ba758114f4af800dabb58395e87f29ad8f2fc53c6ba999a4c15bd5601a5f47d1101b7e46c36b1c355edf9dce9558cf9bdd298d1eadd2b10f6715915044");
    test_done();
    return 0;
}
