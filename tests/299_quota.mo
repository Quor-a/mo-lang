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
    # 配额:index 行数 >= 2 → 507
    let fd: i64 = fopen("/tmp/t299idx.txt", 0, 0);
    if fd >= 0 {
        let n: i64 = fread(fd, &T_IDX, 8000);
        fclose(fd);
        let lc: i64 = 0;
        let i: i64 = 0;
        while i < n {
            if load8(T_IDX + i) == 10 { lc = lc + 1; }
            i = i + 1;
        }
        if lc >= 2 { return http_make_resp(507, "Insufficient Storage", "text/plain", "quota", 5); }
    }
    sha256_hex(&HS_BODY, HS_BLEN, &T_SHA);
    strcpy(&T_BUF, "");
    strcat(&T_BUF, "pk299 ");
    strcat(&T_BUF, &T_SHA);
    strcat(&T_BUF, "\n");
    fd = fopen("/tmp/t299idx.txt", 1089, 438);
    fwrite(fd, &T_BUF, strlen(&T_BUF));
    fclose(fd);
    return http_make_resp(201, "Created", "text/plain", "ok", 2);
}

fn main() -> i64 {
    syscall(87, "/tmp/t299idx.txt", 0, 0, 0, 0);
    let pid: i64 = fork();
    if pid == 0 {
        http_route("POST", "/pub/:file", &h_up);
        http_serve(18942, 8);
        exit(0);
    }
    sleep_ns(200000000);
    let i: i64 = 0;
    while i < 512 {
        store8(&T_BODY + i, 65 + (i % 26));
        i = i + 1;
    }
    # push 1 → 201
    let b: i64 = tcp_http_post_gzip("/pub/a.tar.gz?name=a&version=1.0.0", "127.0.0.1", 18942, &T_BODY, 512, &T_BUF, 65536, &T_STAT);
    if T_STAT != 201 { print("q1:"); print_i64(T_STAT); print("\n"); exit(1); }
    # push 2 → 201
    b = tcp_http_post_gzip("/pub/b.tar.gz?name=b&version=1.0.0", "127.0.0.1", 18942, &T_BODY, 512, &T_BUF, 65536, &T_STAT);
    if T_STAT != 201 { print("q2:"); print_i64(T_STAT); print("\n"); exit(1); }
    # push 3 → 507
    b = tcp_http_post_gzip("/pub/c.tar.gz?name=c&version=1.0.0", "127.0.0.1", 18942, &T_BODY, 512, &T_BUF, 65536, &T_STAT);
    if T_STAT != 507 { print("q3:"); print_i64(T_STAT); print("\n"); exit(1); }
    print("QUOTA_OK\n");
    return 0;
}
