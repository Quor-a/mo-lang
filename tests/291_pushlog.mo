import "httpcli.mo";
import "httpsrv.mo";
import "str.mo";
import "io.mo";
# expect: 0
var T_BUF: [65536] byte = 0;
var T_STAT: i64 = 0;
var T_BODY: [8192] byte = 0;
var T_LOG: [4096] byte = 0;

fn h_up(u: i64, a: i64) -> i64 {
    return http_make_resp(201, "Created", "text/plain", "ok", 2);
}

fn main() -> i64 {
    let pid: i64 = fork();
    if pid == 0 {
        http_route("POST", "/up/:file", &h_up);
        http_log("/tmp/t291log.txt");
        http_serve(18932, 8);
        exit(0);
    }
    sleep_ns(200000000);
    # ① gzip POST 上传 6000B → 201
    let i: i64 = 0;
    while i < 750 {
        strcpy(&T_BODY + i * 8, "MOPKG255");
        i = i + 1;
    }
    let b: i64 = tcp_http_post_gzip("/up/pk255-1.0.0.tar.gz?name=pk255&version=1.0.0", "127.0.0.1", 18932, &T_BODY, 6000, &T_BUF, 65536, &T_STAT);
    if b < 0 { print("p1:"); print_i64(b); print("\n"); exit(1); }
    if T_STAT != 201 { print("p2:"); print_i64(T_STAT); print("\n"); exit(1); }
    # ② 日志:GET 一次后 grep 日志文件
    b = tcp_http_req_port("GET", "/ping", "127.0.0.1", 18932, 0, 0, &T_BUF, 4096, &T_STAT);
    sleep_ns(100000000);
    let fd: i64 = fopen("/tmp/t291log.txt", 0, 0);
    if fd < 0 { print("l1\n"); exit(1); }
    let ln: i64 = fread(fd, &T_LOG, 4095);
    fclose(fd);
    store8(&T_LOG + ln, 0);
    if strstr(&T_LOG, "POST /up/pk255-1.0.0.tar.gz") < 0 { print("l2:"); print(&T_LOG); print("\n"); exit(1); }
    if strstr(&T_LOG, "GET /ping") < 0 { print("l3:"); print(&T_LOG); print("\n"); exit(1); }
    print("PLOG_OK\n");
    return 0;
}
