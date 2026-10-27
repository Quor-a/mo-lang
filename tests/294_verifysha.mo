import "httpcli.mo";
import "httpsrv.mo";
import "crypto.mo";
import "str.mo";
import "io.mo";
# expect: 0
var T_BUF: [65536] byte = 0;
var T_STAT: i64 = 0;
var T_BODY: [4096] byte = 0;
var T_IDX: [8192] byte = 0;
var T_SHA: [80] byte = 0;

fn h_up(u: i64, a: i64) -> i64 {
    http_query_param("version");
    # v1.258 入库逻辑复刻:index 去重(过滤同名旧行)+ sha256 第三列
    strcpy(&T_IDX, "/tmp/t294idx.txt");
    let fd: i64 = fopen(&T_IDX, 0, 0);
    if fd >= 0 {
        let n: i64 = fread(fd, &T_BUF, 65000);
        fclose(fd);
        if n > 0 {
            store8(&T_BUF + n, 0);
            let w: i64 = 0;
            let cur: i64 = 0;
            while cur < n {
                let nl: i64 = strstr(&T_BUF + cur, "\n");
                if nl < 0 { nl = n - cur; }
                let match: i64 = 0;
                if strstr(&T_BUF + cur, "pk294") == 0 {
                    if load8(T_BUF + cur + 5) == 32 { match = 1; }
                }
                if match == 0 {
                    let k: i64 = 0;
                    while k <= nl {
                        store8(&T_BUF + w + k, load8(T_BUF + cur + k));
                        k = k + 1;
                    }
                    w = w + nl + 1;
                }
                cur = cur + nl + 1;
            }
            fd = fopen(&T_IDX, 577, 438);
            fwrite(fd, &T_BUF, w);
            fclose(fd);
        }
    }
    sha256_hex(&HS_BODY, HS_BLEN, &T_SHA);
    strcpy(&T_BUF, "");
    strcat(&T_BUF, "pk294 ");
    strcat(&T_BUF, &HS_HVAL);
    strcat(&T_BUF, " ");
    strcat(&T_BUF, &T_SHA);
    strcat(&T_BUF, "\n");
    fd = fopen(&T_IDX, 1089, 438);
    fwrite(fd, &T_BUF, strlen(&T_BUF));
    fclose(fd);
    return http_make_resp(201, "Created", "text/plain", "ok", 2);
}

fn main() -> i64 {
    syscall(87, "/tmp/t294idx.txt", 0, 0, 0, 0);
    let pid: i64 = fork();
    if pid == 0 {
        http_route("POST", "/publish/:file", &h_up);
        http_serve(18936, 8);
        exit(0);
    }
    sleep_ns(200000000);
    # ① push v1.0.0(1024B)
    let i: i64 = 0;
    while i < 1024 {
        store8(&T_BODY + i, 65 + (i % 26));
        i = i + 1;
    }
    let b: i64 = tcp_http_post_gzip("/publish/pk294-1.0.0.tar.gz?name=pk294&version=1.0.0", "127.0.0.1", 18936, &T_BODY, 1024, &T_BUF, 65536, &T_STAT);
    if T_STAT != 201 { print("s1:"); print_i64(T_STAT); print("\n"); exit(1); }
    # ② push v2.0.0(2048B,同包名)→ 去重后 index 应只有 1 行
    i = 0;
    while i < 2048 {
        store8(&T_BODY + i, 97 + (i % 26));
        i = i + 1;
    }
    b = tcp_http_post_gzip("/publish/pk294-2.0.0.tar.gz?name=pk294&version=2.0.0", "127.0.0.1", 18936, &T_BODY, 2048, &T_BUF, 65536, &T_STAT);
    if T_STAT != 201 { print("s2:"); print_i64(T_STAT); print("\n"); exit(1); }
    # ③ 读 index:恰好 1 行 pk294,version=2.0.0,sha 与本地一致
    let fd: i64 = fopen("/tmp/t294idx.txt", 0, 0);
    if fd < 0 { print("s3\n"); exit(1); }
    let n: i64 = fread(fd, &T_IDX, 8000);
    fclose(fd);
    store8(&T_IDX + n, 0);
    if strstr(&T_IDX, "1.0.0") >= 0 { print("s4:"); print(&T_IDX); print("\n"); exit(1); }
    if strstr(&T_IDX, "pk294 2.0.0 ") < 0 { print("s5:"); print(&T_IDX); print("\n"); exit(1); }
    # index 只有 pk294 1 行(行数=1)
    let lines: i64 = 0;
    i = 0;
    while i < n {
        if load8(T_IDX + i) == 10 { lines = lines + 1; }
        i = i + 1;
    }
    if lines != 1 { print("s6:"); print_i64(lines); print("\n"); exit(1); }
    sha256_hex(&T_BODY, 2048, &T_SHA);
    if strstr(&T_IDX, &T_SHA) < 0 { print("s7\n"); exit(1); }
    print("VSHA_OK\n");
    return 0;
}
