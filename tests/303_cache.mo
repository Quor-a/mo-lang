import "crypto.mo";
import "str.mo";
import "io.mo";
import "fs.mo";
import "net.mo";
# expect: 0
var C_BUF: [65536] byte = 0;
var C_SHA: [80] byte = 0;

fn main() -> i64 {
    # ① 数据 1234B,算 sha
    let i: i64 = 0;
    while i < 1234 {
        store8(&C_BUF + i, 65 + (i % 26));
        i = i + 1;
    }
    sha256_hex(&C_BUF, 1234, &C_SHA);
    # ② 写缓存文件(模拟 pkg_http_dep 缓存写入)+ tgz 副本
    let fd: i64 = fopen("/tmp/t303cache.sha", 577, 438);
    if fd < 0 { print("c1\n"); exit(1); }
    fwrite(fd, &C_SHA, strlen(&C_SHA));
    fclose(fd);
    fd = fopen("/tmp/t303cache.tgz", 577, 438);
    fwrite(fd, &C_BUF, 1234);
    fclose(fd);
    # ③ 模拟缓存命中:读副本 → sha → 与缓存 .sha 一致
    fd = fopen("/tmp/t303cache.tgz", 0, 0);
    if fd < 0 { print("c2\n"); exit(1); }
    let n: i64 = fread(fd, &C_BUF, 65000);
    fclose(fd);
    sha256_hex(&C_BUF, n, &C_BUF);
    fd = fopen("/tmp/t303cache.sha", 0, 0);
    let m: i64 = fread(fd, &C_SHA, 78);
    fclose(fd);
    store8(&C_SHA + m, 0);
    if strstr(&C_SHA, &C_BUF) < 0 { print("c3\n"); exit(1); }
    syscall(87, "/tmp/t303cache.sha", 0, 0, 0, 0);
    syscall(87, "/tmp/t303cache.tgz", 0, 0, 0, 0);
    print("CACHE_OK\n");
    return 0;
}
