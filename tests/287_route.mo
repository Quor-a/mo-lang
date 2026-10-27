import "httpsrv.mo";
import "httpcli.mo";
import "str.mo";
import "io.mo";
# expect: 0

var T7_BUF: [4096] byte = 0;
var T7_STAT: i64 = 0;

fn h_user(u: i64, a: i64) -> i64 {
    strcpy(&HS_KV, "{\"id\":\"");
    strcat(&HS_KV, &HS_PARAM);
    strcat(&HS_KV, "\"}");
    return http_make_resp(200, "OK", "application/json", &HS_KV, strlen(&HS_KV));
}

fn h_echo(u: i64, a: i64) -> i64 {
    # ?name=xx → 回显解码后值
    if http_query_param("name") < 0 {
        strcpy(&HS_KV, "none");
    } else {
        strcpy(&HS_KV, &HS_HVAL);
    }
    return http_make_resp(200, "OK", "text/plain", &HS_KV, strlen(&HS_KV));
}

fn main() -> i64 {
    http_route("GET", "/user/:id", &h_user);
    http_route("GET", "/echo", &h_echo);
    let pid: i64 = fork();
    if pid == 0 {
        http_serve(18710, 8);
        exit(0);
    }
    sleep_ns(200000000);
    let b: i64 = tcp_http_req_port("GET", "/user/42", "127.0.0.1", 18710, 0, 0, &T7_BUF, 4096, &T7_STAT);
    if b != 11 { print("p1:"); print_i64(b); print(" ["); print(&T7_BUF); print("]\n"); exit(1); }
    if streq(&T7_BUF, "{\"id\":\"42\"}") != 1 { print("p2\n"); exit(1); }
    b = tcp_http_req_port("GET", "/echo?name=mo%20q", "127.0.0.1", 18710, 0, 0, &T7_BUF, 4096, &T7_STAT);
    if streq(&T7_BUF, "mo q") != 1 { print("p3:"); print(&T7_BUF); print("\n"); exit(1); }
    print("ROUTE_OK\n");
    exit(0);
    return 0;
}
