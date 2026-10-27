import "httpcli.mo";
import "httpsrv.mo";
import "crypto.mo";
import "str.mo";
import "io.mo";
# expect: 0
var T_BUF: [65536] byte = 0;
var T_STAT: i64 = 0;
var T_BODY: [512] byte = 0;
var T_IDX: [8192] byte = 0;
var T_SHA: [80] byte = 0;

fn h_up(u: i64, a: i64) -> i64 {
    sha256_hex(&HS_BODY, HS_BLEN, &T_SHA);
    strcpy(&T_IDX, "");
    strcat(&T_IDX, "pk301 1.0.0 ");
    strcat(&T_IDX, &T_SHA);
    strcat(&T_IDX, "\n");
    let fd: i64 = fopen("/tmp/t301idx.txt", 1089, 438);
    fwrite(fd, &T_IDX, strlen(&T_IDX));
    fclose(fd);
    return http_make_resp(201, "Created", "text/plain", "ok", 2);
}

fn h_del(u: i64, a: i64) -> i64 {
    if http_query_param("token") < 0 { return http_make_resp(403, "Forbidden", "text/plain", "403", 3); }
    if streq(&HS_HVAL, "tk301") != 1 { return http_make_resp(403, "Forbidden", "text/plain", "403", 3); }
    syscall(87, "/tmp/t301idx.txt", 0, 0, 0, 0);
    return http_make_resp(200, "OK", "text/plain", "deleted", 7);
}

fn main() -> i64 {
    let pid: i64 = fork();
    if pid == 0 {
        http_route("POST", "/pub/:file", &h_up);
        http_route("DELETE", "/pkg/:file", &h_del);
        http_serve(18944, 8);
        exit(0);
    }
    sleep_ns(200000000);
    let i: i64 = 0;
    while i < 512 {
        store8(&T_BODY + i, 65 + (i % 26));
        i = i + 1;
    }
    # push → 201
    let b: i64 = tcp_http_post_gzip("/pub/a.tar.gz?name=pk301&version=1.0.0", "127.0.0.1", 18944, &T_BODY, 512, &T_BUF, 65536, &T_STAT);
    if T_STAT != 201 { print("d1:"); print_i64(T_STAT); print("\n"); exit(1); }
    # DELETE 无 token → 403
    b = tcp_http_req_port("DELETE", "/pkg/a.tar.gz", "127.0.0.1", 18944, 0, 0, &T_BUF, 65536, &T_STAT);
    if T_STAT != 403 { print("d2:"); print_i64(T_STAT); print("\n"); exit(1); }
    # DELETE 带 token → 200
    b = tcp_http_req_port("DELETE", "/pkg/a.tar.gz?token=tk301", "127.0.0.1", 18944, 0, 0, &T_BUF, 65536, &T_STAT);
    if T_STAT != 200 { print("d3:"); print_i64(T_STAT); print("\n"); exit(1); }
    # index 已清
    let fd: i64 = fopen("/tmp/t301idx.txt", 0, 0);
    if fd >= 0 { print("d4\n"); exit(1); }
    print("DEL_OK\n");
    return 0;
}
