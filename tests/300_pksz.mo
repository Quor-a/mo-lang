import "httpcli.mo";
import "httpsrv.mo";
import "str.mo";
import "io.mo";
# expect: 0
var T_BUF: [65536] byte = 0;
var T_STAT: i64 = 0;
var T_BODY: [16384] byte = 0;

fn h_up(u: i64, a: i64) -> i64 {
    if HS_BLEN > 8000 { return http_make_resp(413, "Payload Too Large", "text/plain", "pksize", 6); }
    return http_make_resp(201, "Created", "text/plain", "ok", 2);
}

fn main() -> i64 {
    let pid: i64 = fork();
    if pid == 0 {
        http_route("POST", "/pub/:file", &h_up);
        http_serve(18943, 8);
        exit(0);
    }
    sleep_ns(200000000);
    let i: i64 = 0;
    while i < 16384 {
        store8(&T_BODY + i, 65 + (i % 26));
        i = i + 1;
    }
    # ① 8000B → 201
    let b: i64 = tcp_http_post_gzip("/pub/a.tar.gz?name=a&version=1.0.0", "127.0.0.1", 18943, &T_BODY, 8000, &T_BUF, 65536, &T_STAT);
    if T_STAT != 201 { print("z1:"); print_i64(T_STAT); print("\n"); exit(1); }
    # ② 9000B → 413
    b = tcp_http_post_gzip("/pub/b.tar.gz?name=b&version=1.0.0", "127.0.0.1", 18943, &T_BODY, 9000, &T_BUF, 65536, &T_STAT);
    if T_STAT != 413 { print("z2:"); print_i64(T_STAT); print("\n"); exit(1); }
    print("PKSZ_OK\n");
    return 0;
}
