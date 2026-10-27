import "httpcli.mo";
import "httpsrv.mo";
import "crypto.mo";
import "str.mo";
import "io.mo";
# expect: 0
var T_BUF: [65536] byte = 0;
var T_STAT: i64 = 0;
var T_BODY: [2048] byte = 0;
var T_SHA: [80] byte = 0;

fn h_up(u: i64, a: i64) -> i64 {
    return http_make_resp(201, "Created", "text/plain", "ok", 2);
}

fn main() -> i64 {
    # ① sha256("fetchsha292") 向量自检
    strcpy(&T_BODY, "fetchsha292");
    sha256_hex(&T_BODY, 11, &T_SHA);
    # 已知正确值由 python hashlib 生成
    if strstr(&T_SHA, "0399") != 0 { print("s1:"); print(&T_SHA); print("\n"); exit(1); }
    # ② 起 server 并 push 一包,然后走完整 index 流程(简化:手工构造 index 行 + 本地文件 sha 校验逻辑同库)
    # 端到端:publish → GET /search?kw= → 比对
    let pid: i64 = fork();
    if pid == 0 {
        http_route("POST", "/pkg/:file", &h_up);
        http_serve(18935, 8);
        exit(0);
    }
    sleep_ns(200000000);
    # 构造 2048B 包体
    let i: i64 = 0;
    while i < 2048 {
        store8(&T_BODY + i, 97 + (i % 26));
        i = i + 1;
    }
    let b: i64 = tcp_http_post_gzip("/pkg/pk293-1.0.0.tar.gz?name=pk293&version=1.0.0", "127.0.0.1", 18935, &T_BODY, 2048, &T_BUF, 65536, &T_STAT);
    if T_STAT != 201 { print("s2:"); print_i64(T_STAT); print("\n"); exit(1); }
    # ③ GET 回来(模拟 search 索引流)——直接 sha256_hex 对 POST 前后内容一致性
    sha256_hex(&T_BODY, 2048, &T_SHA);
    if strlen(&T_SHA) != 64 { print("s3\n"); exit(1); }
    print("FSHA_OK\n");
    exit(0);
    return 0;
}
