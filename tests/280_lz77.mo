import "archive.mo";
import "io.mo";
# expect: 0

fn main() -> i64 {
    let rc: i64 = gzip_write("/tmp/gzsrc/blob.bin", "/tmp/mo244.gz");
    if rc != 0 { print("w="); print_i64(rc); print("\n"); return 1; }
    let rc2: i64 = gunzip_file("/tmp/mo244.gz", "/tmp/mo244.bin");
    if rc2 != 0 { print("g="); print_i64(rc2); print("\n"); return 1; }
    print("LZ77_OK\n");
    return 0;
}
