import "httpsrv.mo";
import "httpcli.mo";
import "str.mo";
import "io.mo";
# expect: 0

var T6_BUF: [16384] byte = 0;
var T6_SRC: [8192] byte = 0;
var T6_STAT: i64 = 0;
var T6_BODY: [8192] byte = 0;

fn h_big(u: i64, a: i64) -> i64 {
    # 8000 字节重复 body（gzip 应压到几百字节）
    let i: i64 = 0;
    while i < 1000 {
        strcpy(&T6_BODY + i * 8, "abcdefgh");
        i = i + 1;
    }
    return http_make_resp(200, "OK", "text/plain", &T6_BODY, 8000);
}

fn main() -> i64 {
    http_route("GET", "/big", &h_big);
    let pid: i64 = fork();
    if pid == 0 {
        http_serve(18700, 8);
        exit(0);
    }
    sleep_ns(200000000);
    let b: i64 = tcp_http_req_port("GET", "/big", "127.0.0.1", 18700, 0, 0, &T6_BUF, 16384, &T6_STAT);
    if b != 8000 { print("g1:"); print_i64(b); print("\n"); exit(1); }
    # 内容校验:每 8 字节 abcdefgh
    let i: i64 = 0;
    while i < 8000 {
        if load8(&T6_BUF + i) != 97 + (i & 7) { print("g2:"); print_i64(i); print("\n"); exit(1); }
        i = i + 1;
    }
    print("GZHTTP_OK\n");
    exit(0);
    return 0;
}
