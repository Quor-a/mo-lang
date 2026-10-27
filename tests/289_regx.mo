import "httpcli.mo";
import "httpsrv.mo";
import "str.mo";
import "io.mo";
# expect: 0

var T9_BUF: [65536] byte = 0;
var T9_STAT: i64 = 0;
var RS_BUF: [65536] byte = 0;
var RS_PATH: [512] byte = 0;
var RS_IDX: [32768] byte = 0;
var RS_OUT: [32768] byte = 0;
var RS_FD: i64 = 0;
var RS_N: i64 = 0;
var RS_I: i64 = 0;
var RS_LP: i64 = 0;
var RS_KW: [128] byte = 0;

fn h_pkg(u: i64, a: i64) -> i64 {
    strcpy(&RS_PATH, "/tmp/regtest/registry/");
    strcat(&RS_PATH, &HS_PARAM);
    RS_FD = fopen(&RS_PATH, 0, 0);
    if RS_FD < 0 { return http_make_resp(404, "Not Found", "text/plain", "404", 3); }
    RS_N = fread(RS_FD, &RS_BUF, 65536);
    fclose(RS_FD);
    if RS_N <= 0 { return http_make_resp(404, "Not Found", "text/plain", "404", 3); }
    return http_make_resp(200, "OK", "application/gzip", &RS_BUF, RS_N);
}

fn h_search(u: i64, a: i64) -> i64 {
    RS_FD = fopen("/tmp/regtest/registry/index.txt", 0, 0);
    if RS_FD < 0 { return http_make_resp(404, "Not Found", "text/plain", "404", 3); }
    RS_N = fread(RS_FD, &RS_IDX, 32768);
    fclose(RS_FD);
    strcpy(&RS_OUT, "");
    if http_query_param("kw") >= 0 {
        strcpy(&RS_KW, &HS_HVAL);
        RS_I = 0;
        while RS_I < RS_N {
            RS_LP = strstr(&RS_IDX + RS_I, "\n");
            if RS_LP < 0 { RS_LP = RS_N - RS_I; }
            if RS_LP > 0 {
                store8(&RS_IDX + RS_I + RS_LP, 0);
                if strstr(&RS_IDX + RS_I, &RS_KW) >= 0 {
                    strcat(&RS_OUT, &RS_IDX + RS_I);
                    strcat(&RS_OUT, "\n");
                }
            }
            RS_I = RS_I + RS_LP + 1;
        }
        if strlen(&RS_OUT) == 0 { strcpy(&RS_OUT, "none"); }
    } else {
        strcpy(&RS_OUT, &RS_IDX);
    }
    return http_make_resp(200, "OK", "text/plain", &RS_OUT, strlen(&RS_OUT));
}

fn main() -> i64 {
    syscall(83, "/tmp/regtest", 493, 0, 0, 0, 0);
    syscall(83, "/tmp/regtest/registry", 493, 0, 0, 0, 0);
    let fd: i64 = fopen("/tmp/regtest/registry/index.txt", 577, 420);
    if fd < 0 { print("r0\n"); return 1; }
    fwrite(fd, "xorq16 1.0.0\nkvjson 1.1.0\nq16mo 1.0.0\n", 38);
    fclose(fd);
    fd = fopen("/tmp/regtest/registry/xorq16-1.0.0.tar.gz", 577, 420);
    fwrite(fd, "PKDATA", 6);
    fclose(fd);
    http_route("GET", "/pkg/:file", &h_pkg);
    http_route("GET", "/search", &h_search);
    let pid: i64 = fork();
    if pid == 0 {
        http_serve(18910, 8);
        exit(0);
    }
    sleep_ns(200000000);
    # ① keep-alive 第 1 请求:search?kw=q16
    let b: i64 = tcp_http_ka("GET", "/search?kw=q16", "127.0.0.1", 18910, 0, 0, &T9_BUF, 65536, &T9_STAT);
    if b != 25 { print("s1:"); print_i64(b); print(" ["); print(&T9_BUF); print("]\n"); exit(1); }
    if streq(&T9_BUF, "xorq16 1.0.0\nq16mo 1.0.0\n") != 1 { print("s2:"); print(&T9_BUF); print("\n"); exit(1); }
    # ② 同连接复用:全量 search
    b = tcp_http_ka("GET", "/search", "127.0.0.1", 18910, 0, 0, &T9_BUF, 65536, &T9_STAT);
    if b != 38 { print("s3:"); print_i64(b); print("\n"); exit(1); }
    # ③ pkg fetch
    b = tcp_http_ka("GET", "/pkg/xorq16-1.0.0.tar.gz", "127.0.0.1", 18910, 0, 0, &T9_BUF, 65536, &T9_STAT);
    if b != 6 { print("s4:"); print_i64(b); print("\n"); exit(1); }
    if streq(&T9_BUF, "PKDATA") != 1 { print("s5\n"); exit(1); }
    # ④ 404
    b = tcp_http_ka("GET", "/pkg/none.tar.gz", "127.0.0.1", 18910, 0, 0, &T9_BUF, 65536, &T9_STAT);
    if T9_STAT != 404 { print("s6:"); print_i64(T9_STAT); print("\n"); exit(1); }
    tcp_http_ka_close();
    # ⑤ 静态+目录列表+HEAD(第二 server)
    syscall(83, "/tmp/www", 493, 0, 0, 0, 0);
    fd = fopen("/tmp/www/a.html", 577, 420);
    fwrite(fd, "<p>A</p>", 8);
    fclose(fd);
    fd = fopen("/tmp/www/b.txt", 577, 420);
    fwrite(fd, "BB", 2);
    fclose(fd);
    http_static_route("/tmp/www/");
    let pid2: i64 = fork();
    if pid2 == 0 {
        http_serve(18920, 8);
        exit(0);
    }
    sleep_ns(200000000);
    # HEAD
    b = tcp_http_ka("HEAD", "/static/a.html", "127.0.0.1", 18920, 0, 0, &T9_BUF, 65536, &T9_STAT);
    if T9_STAT != 200 { print("h1:"); print_i64(T9_STAT); print("\n"); exit(1); }
    if b != 0 { print("h2:"); print_i64(b); print("\n"); exit(1); }
    # 静态文件
    b = tcp_http_ka("GET", "/static/b.txt", "127.0.0.1", 18920, 0, 0, &T9_BUF, 65536, &T9_STAT);
    if b != 2 || streq(&T9_BUF, "BB") != 1 { print("h3:"); print_i64(b); print("\n"); exit(1); }
    # MIME:html
    b = tcp_http_ka("GET", "/static/a.html", "127.0.0.1", 18920, 0, 0, &T9_BUF, 65536, &T9_STAT);
    if b != 8 || streq(&T9_BUF, "<p>A</p>") != 1 { print("h4:"); print_i64(b); print("\n"); exit(1); }
    # 目录列表
    b = tcp_http_ka("GET", "/static", "127.0.0.1", 18920, 0, 0, &T9_BUF, 65536, &T9_STAT);
    if b <= 0 { print("h5:"); print_i64(b); print("\n"); exit(1); }
    if strstr(&T9_BUF, "a.html") < 0 || strstr(&T9_BUF, "b.txt") < 0 { print("h6:"); print(&T9_BUF); print("\n"); exit(1); }
    tcp_http_ka_close();
    print("REG_OK\n");
    exit(0);
    return 0;
}
