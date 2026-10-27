import "fs.mo";
import "io.mo";
import "str.mo";
# expect: 0

var B: [256] byte = 0;

fn main() -> i64 {
    # mkdir_p + exists
    fs_mkdir_p("/tmp/fsx/a/b");
    if fs_file_exists("/tmp/fsx/a/b") != 1 { print("fail mkdir\n"); return 1; }
    if fs_file_exists("/tmp/fsx/nope") != 0 { print("fail neg\n"); return 1; }
    # size: 写文件后 lseek 探大小
    let fd: i64 = fopen("/tmp/fsx/a/b/f.txt", 577, 438);
    if fd < 0 { print("fail open\n"); return 1; }
    fwrite(fd, "hello-fsx", 9);
    fclose(fd);
    let sz: i64 = fs_file_size("/tmp/fsx/a/b/f.txt");
    if sz != 9 { print("fail size="); print_i64(sz); print("\n"); return 1; }
    if fs_file_size("/tmp/fsx/a/b/nope.txt") != 0 - 1 { print("fail negsize\n"); return 1; }
    # rm
    fs_rm("/tmp/fsx/a/b/f.txt");
    if fs_file_exists("/tmp/fsx/a/b/f.txt") != 0 { print("fail rm\n"); return 1; }
    print("FSX_OK\n");
    return 0;
}
