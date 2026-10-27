import "archive.mo";
import "io.mo";
# expect: 0

fn main() -> i64 {
    # 用 /bin/gzip 生成的真实 dynamic-Huffman 流
    let rc: i64 = gunzip_file("/tmp/gztest_in.tar.gz", "/tmp/gztest_out.tar");
    if rc != 0 { print("rc="); print_i64(rc); print("\n"); return 1; }
    print("GZ_OK\n");
    return 0;
}
