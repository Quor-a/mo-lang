import "net.mo";
import "httpcli.mo";
import "str.mo";
import "io.mo";
# expect: 0

var QS_KEY: [2] i64 = 0;
var QS_VAL: [2] i64 = 0;
var QS_K1: [8] byte = "name";
var QS_V1: [32] byte = "mo lang 1";
var QS_Q: [64] byte = 0;
var QS_BUF: [4096] byte = 0;
var QS_REQ: [1024] byte = 0;
var QS_STAT: i64 = 0;

fn main() -> i64 {
    QS_KEY[0] = &QS_K1;
    QS_VAL[0] = &QS_V1;
    http_build_query(&QS_Q, &QS_KEY, &QS_VAL, 1);
    if streq(&QS_Q, "?name=mo%20lang%201") != 1 { print("q1:"); print(&QS_Q); print("\n"); return 1; }
    let lst: i64 = tcp_listen(18680, 8);
    if lst < 0 { print("s0\n"); return 1; }
    let pid: i64 = fork();
    if pid == 0 {
        let i: i64 = 0;
        while i < 2 {
            let fd: i64 = tcp_accept(lst);
            if fd < 0 { exit(9); }
            let n: i64 = tcp_recv(fd, &QS_REQ, 1000);
            if strstr(&QS_REQ, "GET /chunk") == 0 {
                strcpy(&QS_BUF, "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n4\r\nhell\r\n6\r\nochunk\r\n0\r\n\r\n");
                tcp_send_str(fd, &QS_BUF);
            } else {
                strcpy(&QS_BUF, "HTTP/1.1 201 Created\r\nContent-Length: 5\r\n\r\npost1");
                tcp_send_str(fd, &QS_BUF);
            }
            tcp_close(fd);
            i = i + 1;
        }
        exit(0);
    }
    QS_STAT = 0;
    let b: i64 = tcp_http_req_port("GET", "/chunk", "127.0.0.1", 18680, 0, 0, &QS_BUF, 4096, &QS_STAT);
    if b != 10 { print("c1:"); print_i64(b); print("\n"); exit(1); }
    if streq(&QS_BUF, "hellochunk") != 1 { print("c2:"); print(&QS_BUF); print("\n"); exit(1); }
    if QS_STAT != 200 { print("c3:"); print_i64(QS_STAT); print("\n"); exit(1); }
    strcpy(&QS_REQ, "abcd1");
    b = tcp_http_req_port("POST", "/p", "127.0.0.1", 18680, &QS_REQ, 5, &QS_BUF, 4096, &QS_STAT);
    if b != 5 { print("c4:"); print_i64(b); print("\n"); exit(1); }
    if streq(&QS_BUF, "post1") != 1 { print("c5:"); print(&QS_BUF); print("\n"); exit(1); }
    if QS_STAT != 201 { print("c6:"); print_i64(QS_STAT); print("\n"); exit(1); }
    let st: i64 = 0;
    syscall(61, pid, &st, 0, 0, 0, 0);
    if (st & 255) != 0 { print("c7 st="); print_i64(st); print("\n"); return 1; }
    print("HTTPX_OK\n");
    return 0;
}
