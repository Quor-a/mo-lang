import "httpsrv.mo";
import "httpcli.mo";
import "str.mo";
import "io.mo";
# expect: 0

var T8_BUF: [4096] byte = 0;
var T8_STAT: i64 = 0;

fn main() -> i64 {
    # 造静态文件
    syscall(83, "/tmp/www", 493, 0, 0, 0, 0);   # mkdir(已存在忽略)
    let fd: i64 = fopen("/tmp/www/hello.html", 577, 420);
    if fd < 0 { print("w1\n"); return 1; }
    fwrite(fd, "<h1>hi mo</h1>", 14);
    fclose(fd);
    http_static_route("/tmp/www/");
    let pid: i64 = fork();
    if pid == 0 {
        http_serve(18720, 8);
        exit(0);
    }
    sleep_ns(200000000);
    let b: i64 = tcp_http_req_port("GET", "/static/hello.html", "127.0.0.1", 18720, 0, 0, &T8_BUF, 4096, &T8_STAT);
    if b != 14 { print("f1:"); print_i64(b); print(" ["); print(&T8_BUF); print("]\n"); exit(1); }
    if streq(&T8_BUF, "<h1>hi mo</h1>") != 1 { print("f2\n"); exit(1); }
    if T8_STAT != 200 { print("f3\n"); exit(1); }
    # 404
    b = tcp_http_req_port("GET", "/static/nope.html", "127.0.0.1", 18720, 0, 0, &T8_BUF, 4096, &T8_STAT);
    if T8_STAT != 404 { print("f4:"); print_i64(T8_STAT); print("\n"); exit(1); }
    print("STATIC_OK\n");
    exit(0);
    return 0;
}
