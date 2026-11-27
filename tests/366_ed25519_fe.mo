import "ed25519.mo";
import "assert.mo";
import "io.mo";

fn big_i(v: i64) -> i64 { return big_from_i64(v); }

fn main() -> i64 {
    fe_init();
    # p-1 + 1 = 0
    let pm1: i64 = fe_sub(big_i(0), big_i(1));
    let zero: i64 = fe_add(pm1, big_i(1));
    assert_eq("p-1+1==0", fe_is_zero(zero), 1);
    # 2^255 mod p == 19
    let two: i64 = big_i(2);
    let t: i64 = big_i(1);
    let i: i64 = 0;
    while i < 255 {
        t = fe_mul(t, two);
        i = i + 1;
    }
    assert_eq("2^255 mod p == 19", fe_eq(t, big_i(19)), 1);
    # 逆：3 * inv(3) == 1
    let three: i64 = big_i(3);
    let inv3: i64 = fe_inv(three);
    assert_eq("3*inv(3)==1", fe_eq(fe_mul(three, inv3), big_i(1)), 1);
    # bytes 往返
    let b: [32] byte = 0;
    b[0] = 1;
    b[31] = 2;
    let v: i64 = fe_from_bytes(&b);
    let o: [32] byte = 0;
    fe_to_bytes(v, &o);
    assert_eq("bytes roundtrip b0", o[0], 1);
    assert_eq("bytes roundtrip b31", o[31], 2);
    # sqrt(-1)？先不做。负 fe_to_bytes 已含规约。
    test_done();
    return 0;
}
