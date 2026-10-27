import "httpcli.mo";
import "httpsrv.mo";
import "str.mo";
import "io.mo";
import "net.mo";
# expect: 0
var T_BUF: [65536] byte = 0;
var T_STAT: i64 = 0;
var T_BODY: [2048] byte = 0;

fn h_st(u: i64, a: i64) -> i64 {
    return http_make_resp_etag(200, "OK", "text/plain", &HS_PARAM, strlen(&HS_PARAM));
}

fn main() -> i64 {
    let pid: i64 = fork();
    if pid == 0 {
        http_route("GET", "/st/:file", &h_st);
        http_log("/tmp/t296log.txt");
        http_serve(18938, 8);
        exit(0);
    }
    sleep_ns(200000000);
    # ① 首取 200 + ETag 头(raw:含响应头)
    let b: i64 = tcp_http_req_raw("GET", "/st/abc", "127.0.0.1", 18938, 0, 0, &T_BUF, 65536, &T_STAT);
    if T_STAT != 200 { print("e1:"); print_i64(T_STAT); print("\n"); exit(1); }
    let ep: i64 = strstr(&T_BUF, "ETag: ");
    if ep < 0 { print("e2\n"); exit(1); }
    strcpy(&T_BODY, &T_BUF + ep + 6);
    let eol: i64 = strstr(&T_BODY, "\r");
    store8(&T_BODY + eol, 0);
    # ② If-None-Match → 304 且 304 响应也带 ETag
    # ② If-None-Match → 304 且 304 响应带 Eag 头:v1.260 语义。server 侧 If-None-Match 需要原始请求——req_port 不支持自定义头 → 用 raw 但自定义头无法传……
    # 方案:第二次带不同 path(内容同 → ETag 同),先直连发原始请求:用 tcp 系列手发
    let ip: i64 = ip_parse("127.0.0.1");
    let fd2: i64 = tcp_connect(ip, 18938);
    if fd2 < 0 { print("e2a\n"); exit(1); }
    strcpy(&T_BUF, "GET /st/abc HTTP/1.1\r\nHost: 127.0.0.1\r\nIf-None-Match: ");
    strcat(&T_BUF, &T_BODY);
    strcat(&T_BUF, "\r\nConnection: close\r\n\r\n");
    tcp_send(fd2, &T_BUF, strlen(&T_BUF));
    let got: i64 = 0;
    while 1 {
        let r2: i64 = tcp_recv(fd2, &T_BUF + got, 4096);
        if r2 <= 0 { break; }
        got = got + r2;
        store8(&T_BUF + got, 0);
    }
    tcp_close(fd2);
    if strstr(&T_BUF, "304 Not Modified") < 0 { print("e2b:"); print(&T_BUF); print("\n"); exit(1); }
    if strstr(&T_BUF, "ETag: ") < 0 { print("e2c:"); print(&T_BUF); print("\n"); exit(1); }
    # ③ access.log 有两条 GET /st/abc
    sleep_ns(100000000);
    let fd: i64 = fopen("/tmp/t296log.txt", 0, 0);
    if fd < 0 { print("e4\n"); exit(1); }
    let n: i64 = fread(fd, &T_BUF, 65000);
    fclose(fd);
    store8(&T_BUF + n, 0);
    if strstr(&T_BUF, "GET /st/abc") < 0 { print("e5:"); print(&T_BUF); print("\n"); exit(1); }
    print("ET304_OK\n");
    return 0;
}
