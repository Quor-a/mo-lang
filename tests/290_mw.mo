import "httpcli.mo";
import "httpsrv.mo";
import "str.mo";
import "io.mo";
# expect: 0

var TA_BUF: [65536] byte = 0;
var TA_STAT: i64 = 0;
var TA_BODY: [8192] byte = 0;
var TA_ET: [64] byte = 0;

fn h_upload(u: i64, a: i64) -> i64 {
    # HS_BODY 已透明解压 → 回显
    return http_make_resp(200, "OK", "text/plain", &HS_BODY, HS_BLEN);
}

fn h_et(u: i64, a: i64) -> i64 {
    strcpy(&TA_BODY, "etagbody12345");
    return http_make_resp_etag(200, "OK", "text/plain", &TA_BODY, 13);
}

fn mw_deny(u: i64) -> i64 {
    # 简单演示:拒绝带 X-Deny: 1 头的请求
    if strstr(&HS_REQ, "X-Deny: 1") >= 0 { return 1; }
    return 0;
}

fn main() -> i64 {
    http_route("POST", "/up", &h_upload);
    http_route("GET", "/et", &h_et);
    http_middleware(&mw_deny);
    let pid: i64 = fork();
    if pid == 0 {
        http_serve(18930, 8);
        exit(0);
    }
    sleep_ns(200000000);
    # ① POST gzip 上传:1000 字节重复
    let i: i64 = 0;
    while i < 1000 {
        strcpy(&TA_BODY + i * 8, "abcdefgh");
        i = i + 1;
    }
    let b: i64 = tcp_http_post_gzip("/up", "127.0.0.1", 18930, &TA_BODY, 8000, &TA_BUF, 65536, &TA_STAT);
    if b != 8000 {
        print("u1:"); print_i64(b); print(" b0..7=");
        let di: i64 = 0;
        while di < 8 { print_i64(load8(&TA_BUF + di)); print(","); di = di + 1; }
        print("\n"); exit(1);
    }
    if load8(&TA_BUF + 7999) != 104 { print("u2\n"); exit(1); }   # 'g'
    # ② ETag:首次 200 + ETag;再条件请求 → 304
    b = tcp_http_ka("GET", "/et", "127.0.0.1", 18930, 0, 0, &TA_BUF, 65536, &TA_STAT);
    if b != 13 || TA_STAT != 200 { print("e1:"); print_i64(b); print("\n"); exit(1); }
    # 从响应头取 ETaG?— client 不吐头;server 端 ETag 确定(FNV 同一 body)——直接用 server 逻辑重算?简化:header 在 HC_RB。找:
    let ep: i64 = strstr(&HC_RB, "ETag: ");
    if ep < 0 { print("e2\n"); exit(1); }
    strcpy(&TA_ET, &HC_RB + ep + 6);
    let q: i64 = strstr(&TA_ET, "\r");
    if q >= 0 { store8(&TA_ET + q, 0); }
    # ③ If-None-Match → 304
    b = tcp_http_if_none("/et", "127.0.0.1", 18930, &TA_ET, &TA_BUF, 65536, &TA_STAT);
    if TA_STAT != 304 { print("e3:"); print_i64(TA_STAT); print(" et="); print(&TA_ET); print("\n"); exit(1); }
    # ④ 中间件 403
    strcpy(&HC_REQ, "");
    # 用 raw 带 X-Deny 头:借用 if_none 形式不行——直接 tcp 组请求:
    b = tcp_http_deny_test();
    if TA_STAT != 403 { print("m1:"); print_i64(TA_STAT); print("\n"); exit(1); }
    tcp_http_ka_close();
    print("MW_OK\n");
    exit(0);
    return 0;
}

fn tcp_http_deny_test() -> i64 {
    let fd: i64 = tcp_connect(2130706433, 18930);
    if fd < 0 { return 0 - 1; }
    strcpy(&HC_REQ, "GET /et HTTP/1.1\r\nHost: 127.0.0.1\r\nX-Deny: 1\r\nConnection: close\r\n\r\n");
    tcp_send(fd, &HC_REQ, strlen(&HC_REQ));
    let n: i64 = tcp_recv(fd, &TA_BUF, 4096);
    tcp_close(fd);
    # 状态码
    if strstr(&TA_BUF, " 403 ") >= 0 { TA_STAT = 403; } else { TA_STAT = 0; }
    return n;
}
