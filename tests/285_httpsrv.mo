import "httpsrv.mo";
import "httpcli.mo";
import "str.mo";
import "io.mo";
# expect: 0

var T5_BUF: [4096] byte = 0;
var T5_STAT: i64 = 0;

fn h_hi(u: i64, a: i64) -> i64 {
    strcpy(&HS_KV, "{\"msg\":\"hi\"}");
    return http_make_resp(200, "OK", "application/json", &HS_KV, strlen(&HS_KV));
}

fn main() -> i64 {
    http_route("GET", "/hi", &h_hi);
    let pid: i64 = fork();
    if pid == 0 {
        http_serve(18690, 8);
        exit(0);
    }
    sleep_ns(200000000);
    # ① 200
    let b: i64 = tcp_http_req_port("GET", "/hi", "127.0.0.1", 18690, 0, 0, &T5_BUF, 4096, &T5_STAT);
    if b != 12 { print("s1:"); print_i64(b); print(" ["); print(&T5_BUF); print("]\n"); exit(1); }
    if streq(&T5_BUF, "{\"msg\":\"hi\"}") != 1 { print("s2:"); print(&T5_BUF); print("\n"); exit(1); }
    if T5_STAT != 200 { print("s3\n"); exit(1); }
    # ② 404
    b = tcp_http_req_port("GET", "/nope", "127.0.0.1", 18690, 0, 0, &T5_BUF, 4096, &T5_STAT);
    if b != 3 { print("s4:"); print_i64(b); print("\n"); exit(1); }
    if T5_STAT != 404 { print("s5\n"); exit(1); }
    # ③ 头解析
    b = tcp_http_req_port("GET", "/hi", "127.0.0.1", 18690, 0, 0, &T5_BUF, 4096, &T5_STAT);
    if b != 12 { print("s6\n"); exit(1); }
    print("SRV_OK\n");
    exit(0);
    return 0;
}
