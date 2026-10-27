# expect: 0
# DNS 库：QNAME 编码与 resolv.conf 解析（离线，无网络）
import "io.mo";
import "dns.mo";
import "str.mo";

var host: [64] byte = 0;
var obuf: [128] byte = 0;

fn main() -> i64 {
    # QNAME 编码：www.example.com -> 3www7example3com0
    strcpy(&host, "www.example.com");
    let off: [1] i64 = 0;
    off[0] = 0;
    dns_enc_name(&obuf, &off, &host);
    if off[0] != 17 { return 1; }
    if obuf[0] != 3 { return 2; }
    if obuf[1] != 119 { return 3; }
    if obuf[4] != 7 { return 4; }
    if obuf[12] != 3 { return 5; }
    if obuf[16] != 0 { return 6; }
    # resolv.conf 解析（本机必有；结果应非 0）
    if dns_load_resolv() == 0 {
        if NSADDR == 0 { return 7; }
    }
    return 0;
}
