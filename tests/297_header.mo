import "httpcli.mo";
import "httpsrv.mo";
import "str.mo";
import "io.mo";
# expect: 0
var T_BUF: [65536] byte = 0;
var T_HDR: [256] byte = 0;
var T_STAT: i64 = 0;

fn h_st(u: i64, a: i64) -> i64 {
    return http_make_resp_etag(200, "OK", "text/plain", "body296", 7);
}

fn main() -> i64 {
    let pid: i64 = fork();
    if pid == 0 {
        http_route("GET", "/st/:file", &h_st);
        http_serve(18940, 8);
        exit(0);
    }
    sleep_ns(200000000);
    let b: i64 = tcp_http_req_raw("GET", "/st/x", "127.0.0.1", 18940, 0, 0, &T_BUF, 65536, &T_STAT);
    if b < 0 { print("h1:"); print_i64(b); print("\n"); exit(1); }
    # ① Content-Type
    if http_resp_header(&T_BUF, "Content-Type", &T_HDR) < 0 { print("h2\n"); exit(1); }
    if strstr(&T_HDR, "text/plain") < 0 { print("h3:"); print(&T_HDR); print("\n"); exit(1); }
    # ② ETag
    if http_resp_header(&T_BUF, "ETag", &T_HDR) < 0 { print("h4\n"); exit(1); }
    if strstr(&T_HDR, "W/\"") < 0 { print("h5:"); print(&T_HDR); print("\n"); exit(1); }
    # ③ 不存在的头
    if http_resp_header(&T_BUF, "X-Nope", &T_HDR) >= 0 { print("h6\n"); exit(1); }
    # ④ 状态行
    if strstr(&T_BUF, "HTTP/1.1 200 OK") < 0 { print("h7\n"); exit(1); }
    print("HDR_OK\n");
    return 0;
}
