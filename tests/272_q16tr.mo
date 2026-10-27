import "q16.mo";
import "io.mo";
import "str.mo";
# expect: 0

var S: [32] byte = 0;

fn chk(q: i64, want: ptr, tag: ptr) -> i64 {
    f2sq16(&S, q);
    if streq(&S, want) != 1 { print("fail "); print(tag); print("="); print(&S); print("\n"); return 1; }
    return 0;
}

fn main() -> i64 {
    # exp：e^0=1, e^1=2.7183, e^-1=0.3679
    if chk(q16_exp(0), "1.0000", "e0") != 0 { return 1; }
    if chk(q16_exp(65536), "2.7183", "e1") != 0 { return 1; }
    if chk(q16_exp(0 - 65536), "0.3679", "en1") != 0 { return 1; }
    # log：ln1=0, ln e=1, ln2=0.6931, round-trip
    if chk(q16_log(65536), "0.0000", "ln1") != 0 { return 1; }
    if chk(q16_log(178145), "1.0000", "lne") != 0 { return 1; }   # e≈2.71828
    if chk(q16_log(131072), "0.6931", "ln2") != 0 { return 1; }
    # sin/cos：sin0=0, sin(π/6)=0.5, sin(π/2)=1, cos0=1, sin(π)=0
    if chk(q16_sin(0), "0.0000", "s0") != 0 { return 1; }
    if chk(q16_sin(34313), "0.5000", "s30") != 0 { return 1; }    # π/6≈0.5236
    if chk(q16_sin(102944), "1.0000", "s90") != 0 { return 1; }
    if chk(q16_cos(0), "1.0000", "c0") != 0 { return 1; }
    if chk(q16_sin(205887), "0.0000", "s180") != 0 { return 1; }  # π
    print("Q16TR_OK\n");
    return 0;
}
