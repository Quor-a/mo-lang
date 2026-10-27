import "httpcli.mo";
import "httpsrv.mo";
import "str.mo";
import "io.mo";
# expect: 0
var T_BUF: [65536] byte = 0;
var T_HDR: [256] byte = 0;
var T_STAT: i64 = 0;

fn h_st(u: i64, a: i64) -> i64 {
    return http_make_resp_etag(200, "OK", "text/plain", "kacond", 6);
}

fn main() -> i64 {
    let pid: i64 = fork();
    if pid == 0 {
        http_route("GET", "/st/:file", &h_st);
        http_serve(18941, 8);
        exit(0);
    }
    sleep_ns(200000000);
    # ① ka 首取 200
    let b: i64 = tcp_http_ka_hdr("GET", "/st/a", "127.0.0.1", 18941, 0, 0, 0, &T_BUF, 65536, &T_STAT);
    if T_STAT != 200 || b != 6 { print("k1:"); print_i64(T_STAT); print(" b="); print_i64(b); print("\n"); exit(1); }
    # ② 同连接条件请求:拿 raw 的 ETag——ka_hdr 只给 body……先 raw 取 ETag:
    b = tcp_http_req_raw("GET", "/st/a", "127.0.0.1", 18941, 0, 0, &T_BUF, 65536, &T_STAT);
    if http_resp_header(&T_BUF, "ETag", &T_HDR) < 0 { print("k2\n"); exit(1); }
    strcpy(&T_HDR, "If-None-Match: ");
    # 重新 raw 拿 ETag(上面 T_HDR 被覆盖)——重新组织:
    b = tcp_http_req_raw("GET", "/st/a", "127.0.0.1", 18941, 0, 0, &T_BUF, 65536, &T_STAT);
    let ep: i64 = strstr(&T_BUF, "ETag: ");
    let eol: i64 = strstr(&T_BUF + ep + 6, "\r");
    strcpy(&T_HDR, &T_BUF + ep + 6);
    store8(&T_HDR + eol, 0);
    # 组 extra:
    strcpy(&T_BUF, "If-None-Match: ");
    strcat(&T_BUF, &T_HDR);
    strcat(&T_BUF, "\r\n");
    # ③ ka + If-None-Match → 304
    b = tcp_http_ka_hdr("GET", "/st/a", "127.0.0.1", 18941, &T_BUF, 0, 0, &T_BUF, 65536, &T_STAT);
    if T_STAT != 304 { print("k3:"); print_i64(T_STAT); print("\n"); exit(1); }
    # ④ 再 ka GET 200(连接仍复用)
    b = tcp_http_ka_hdr("GET", "/st/a", "127.0.0.1", 18941, 0, 0, 0, &T_BUF, 65536, &T_STAT);
    if T_STAT != 200 || b != 6 { print("k4:"); print_i64(T_STAT); print(" b="); print_i64(b); print("\n"); exit(1); }
    print("KACOND_OK\n");
    return 0;
}
