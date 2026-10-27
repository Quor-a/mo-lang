import "str.mo";
import "net.mo";
import "io.mo";
# expect: 0

var HB: [64] byte = 0;
var HB2: [64] byte = 0;

fn main() -> i64 {
    # parse_base 全家
    if parse_hex("0xFF") != 255 { print("h1\n"); return 1; }
    if parse_hex("ff") != 255 { print("h2\n"); return 1; }
    if parse_bin("1010") != 10 { print("b1\n"); return 1; }
    if parse_oct("755") != 493 { print("o1\n"); return 1; }
    if parse_base("-2a", 16) != -42 { print("h3\n"); return 1; }
    if parse_base("1101", 2) != 13 { print("b2\n"); return 1; }
    # itoa_base 反向
    str_itoa_base(&HB, 255, 16);
    if streq(&HB, "ff") != 1 { print("h4\n"); return 1; }
    str_itoa_base(&HB, 255, 2);
    if streq(&HB, "11111111") != 1 { print("b3\n"); return 1; }
    str_itoa_base(&HB, 493, 8);
    if streq(&HB, "755") != 1 { print("o2\n"); return 1; }
    # hex round-trip
    strcpy(&HB, "AB"); store8(&HB + 2, 1); store8(&HB + 3, 255);
    hex_encode(&HB2, &HB, 4);
    if streq(&HB2, "414201ff") != 1 { print("x1:"); print(&HB2); print("\n"); return 1; }
    strcpy(&HB, "\x00\x00\x00\x00");
    if hex_decode(&HB, "414201ff") != 4 { print("x2\n"); return 1; }
    
    # url
    url_encode(&HB2, "a b/c?d=e");
    if streq(&HB2, "a%20b%2fc%3fd%3de") != 1 { print("u1:"); print(&HB2); print("\n"); return 1; }
    url_decode(&HB, "a+b%2Fc%3Fd%3De");
    if streq(&HB, "a b/c?d=e") != 1 { print("u2\n"); return 1; }
    # ip
    let ip: i64 = ip_parse("192.168.1.10");
    if ip != 3232235786 { print("i1\n"); return 1; }
    ip_to_str(&HB2, ip);
    if streq(&HB2, "192.168.1.10") != 1 { print("i2:"); print(&HB2); print("\n"); return 1; }
    if ip_parse("1.2.3") != -1 { print("i3\n"); return 1; }
    if ip_parse("256.1.1.1") != -1 { print("i4\n"); return 1; }
    if ip_parse("127.0.0.1") != 2130706433 { print("i5\n"); return 1; }
    print("BASE_OK\n");
    return 0;
}
