import "httpcli.mo";
import "httpsrv.mo";
import "str.mo";
import "io.mo";
# expect: 0
var T_BUF: [65536] byte = 0;
var T_STAT: i64 = 0;
var T_BODY: [512] byte = 0;

fn h_up(u: i64, a: i64) -> i64 {
    return http_make_resp(201, "Created", "text/plain", "ok", 2);
}

fn h_get(u: i64, a: i64) -> i64 {
    if strstr(&HS_PARAM, "gone") >= 0 { return http_make_resp(404, "Not Found", "text/plain", "404", 3); }
    return http_make_resp(200, "OK", "application/gzip", "data", 4);
}

fn h_del(u: i64, a: i64) -> i64 {
    if http_query_param("token") < 0 { return http_make_resp(403, "Forbidden", "text/plain", "403", 3); }
    if streq(&HS_HVAL, "tk302") != 1 { return http_make_resp(403, "Forbidden", "text/plain", "403", 3); }
    return http_make_resp(200, "OK", "text/plain", "deleted", 7);
}

fn main() -> i64 {
    let pid: i64 = fork();
    if pid == 0 {
        http_route("POST", "/pub/:file", &h_up);
        http_route("GET", "/pkg/:file", &h_get);
        http_route("DELETE", "/pkg/:file", &h_del);
        http_serve(18945, 8);
        exit(0);
    }
    sleep_ns(200000000);
    let i: i64 = 0;
    while i < 512 {
        store8(&T_BODY + i, 97 + (i % 26));
        i = i + 1;
    }
    # push → 201
    let b: i64 = tcp_http_post_gzip("/pub/x.tar.gz?name=x&version=1.0.0", "127.0.0.1", 18945, &T_BODY, 512, &T_BUF, 65536, &T_STAT);
    if T_STAT != 201 { print("r1:"); print_i64(T_STAT); print("\n"); exit(1); }
    # HEAD 200(存在性)
    b = tcp_http_req_port("HEAD", "/pkg/x.tar.gz", "127.0.0.1", 18945, 0, 0, &T_BUF, 65536, &T_STAT);
    if T_STAT != 200 { print("r2:"); print_i64(T_STAT); print("\n"); exit(1); }
    # DELETE 无 token 403
    b = tcp_http_req_port("DELETE", "/pkg/x.tar.gz", "127.0.0.1", 18945, 0, 0, &T_BUF, 65536, &T_STAT);
    if T_STAT != 403 { print("r3:"); print_i64(T_STAT); print("\n"); exit(1); }
    # DELETE token 200
    b = tcp_http_req_port("DELETE", "/pkg/x.tar.gz?token=tk302", "127.0.0.1", 18945, 0, 0, &T_BUF, 65536, &T_STAT);
    if T_STAT != 200 { print("r4:"); print_i64(T_STAT); print("\n"); exit(1); }
    print("RERM_OK\n");
    return 0;
}
