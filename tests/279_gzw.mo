import "archive.mo";
import "io.mo";
# expect: 0

fn main() -> i64 {
    let rc: i64 = gzip_write("/tmp/gzsrc/blob.bin", "/tmp/mo242.gz");
    if rc != 0 { print("w="); print_i64(rc); print("\n"); return 1; }
    # 自解 round-trip
    let rc2: i64 = gunzip_file("/tmp/mo242.gz", "/tmp/mo242.bin");
    if rc2 != 0 { print("g="); print_i64(rc2); print("\n"); return 1; }
    print("GZW_OK\n");
    return 0;
}
