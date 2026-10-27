import "httpcli.mo";
import "httpsrv.mo";
import "str.mo";
import "io.mo";
import "crypto.mo";
# expect: 0
var T_BUF: [65536] byte = 0;
var T_STAT: i64 = 0;
var T_BODY: [4096] byte = 0;
var T_SHA: [80] byte = 0;

fn h_up(u: i64, a: i64) -> i64 {
    return http_make_resp(201, "Created", "text/plain", "ok", 2);
}

fn mw_tok() -> i64 {
    if streq(&HS_METHOD, "POST") != 1 { return 0; }
    if http_query_param("token") < 0 { return 1; }
    if streq(&HS_HVAL, "tok292") != 1 { return 1; }
    return 0;
}

fn main() -> i64 {
    let pid: i64 = fork();
    if pid == 0 {
        http_route("POST", "/up/:file", &h_up);
        http_middleware(&mw_tok);
        http_serve(18934, 8);
        exit(0);
    }
    sleep_ns(200000000);
    strcpy(&T_BODY, "auth292");
    # ① 无 token → 403
    let b: i64 = tcp_http_post_gzip("/up/f.bin", "127.0.0.1", 18934, &T_BODY, 7, &T_BUF, 65536, &T_STAT);
    if T_STAT != 403 { print("a1:"); print_i64(T_STAT); print("\n"); exit(1); }
    # ② 错 token → 403
    b = tcp_http_post_gzip("/up/f.bin?token=bad", "127.0.0.1", 18934, &T_BODY, 7, &T_BUF, 65536, &T_STAT);
    if T_STAT != 403 { print("a2:"); print_i64(T_STAT); print("\n"); exit(1); }
    # ③ 对 token → 201
    b = tcp_http_post_gzip("/up/f.bin?token=tok292", "127.0.0.1", 18934, &T_BODY, 7, &T_BUF, 65536, &T_STAT);
    if T_STAT != 201 { print("a3:"); print_i64(T_STAT); print("\n"); exit(1); }
    # ④ sha256 已知向量:sha256("abc") = ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
    strcpy(&T_BODY, "abc");
    sha256_hex(&T_BODY, 3, &T_SHA);
    if strstr(&T_SHA, "ba7816bf") != 0 { print("s1:"); print(&T_SHA); print("\n"); exit(1); }
    print("AUTH_OK\n");
    return 0;
}
