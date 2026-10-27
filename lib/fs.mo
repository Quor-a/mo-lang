import "str.mo";
import "err.mo";

# 文件与标准输入输出的薄封装
#   全部是对 syscall 的直接包装，不做缓冲
#   出错时返回 -1（与 C 的惯例一致）
#
# 现在失败时还会把原因写进 lib/err.mo：
#   if read_file(p, buf, cap) < 0 { print(err_msg()); print(err_where()); }
# 返回值语义没变，所以既有调用方不需要改一行就能拿到诊断信息。

# open(path, flags, mode) -> fd 或 -1
#   flags: 0=只读 O_CREAT|O_WRONLY|O_TRUNC=577
fn fopen(path: i64, flags: i64, mode: i64) -> i64 {
    let fd: i64 = syscall(2, path, flags, mode, 0, 0);
    if fd < 0 {
        err_set(err_from_errno(fd), "cannot open file", "fopen");
        return -1;
    }
    err_clear();
    return fd;
}

# read(fd, buf, n) -> 读到的字节数（0 表示 EOF，-1 表示出错）
fn fread(fd: i64, buf: i64, n: i64) -> i64 {
    return syscall(0, fd, buf, n, 0, 0, 0);
}

# write(fd, buf, n) -> 写入的字节数
fn fwrite(fd: i64, buf: i64, n: i64) -> i64 {
    return syscall(1, fd, buf, n, 0, 0, 0);
}

fn fclose(fd: i64) -> i64 {
    return syscall(3, fd, 0, 0, 0, 0, 0);
}

# 输出到 stdout
fn fputs(s: i64) -> i64 {
    return syscall(1, 1, s, strlen(s), 0, 0, 0);
}

# 一次性把文件读进 buf，返回字节数；失败返回 -1
# 会在末尾补一个 0，方便当字符串用。buf 至少要能装 n+1 字节。
fn read_file(path: i64, buf: i64, cap: i64) -> i64 {
    let fd: i64 = syscall(2, path, 0, 0, 0, 0);
    if fd < 0 {
        # 直接调 syscall 而不走 fopen：fopen 已经在失败时设过 err 了，
        # 这里再走一次是重复；但语义上要的是"read_file 失败"这个位置。
        err_set(err_from_errno(fd), "cannot open file", "read_file");
        return -1;
    }
    let n: i64 = fread(fd, buf, cap - 1);
    fclose(fd);
    if n < 0 {
        return -1;
    }
    store8(buf + n, 0);
    return n;
}

# ---------- 目录列表（v1.193.0）----------
# getdents64 最小封装：把 dir 下条目名存进 names（i64 指针数组，指向 DNAME 池），
# 返回个数（不含 "." ".."）。单线程用，DNAME 池 16KB。
var DNAME: [16384] byte = 0;
var DNAM_I: i64 = 0;
var DBUF: [4096] byte = 0;

# fs_file_exists(path)：存在且可 stat 返回 1，否则 0（stat=4 x86_64 → newfstatat）。
fn fs_file_exists(path: ptr) -> i64 {
    # statx 最简：用 open 探测（O_RDONLY=0），能开=存在。目录也能开。
    let fd: i64 = fopen(path, 0, 0);
    if fd >= 0 {
        fclose(fd);
        return 1;
    }
    return 0;
}

# fs_file_size(path)：文件字节数；不存在返 -1。lseek(fd,0,SEEK_END=2)。
var FS_SB: [128] byte = 0;

fn fs_file_size(path: ptr) -> i64 {
    let fd: i64 = fopen(path, 0, 0);
    if fd < 0 { return 0 - 1; }
    # lseek x86_64=8 → aarch64 62
    let sz: i64 = syscall(8, fd, 0, 2, 0, 0, 0);
    fclose(fd);
    return sz;
}

# fs_mkdir_p(path)：逐级建目录（按 '/' 扫描，mkdirat 语义已由 mo2x 适配）。
var FS_MK: [1024] byte = 0;

fn fs_mkdir_p(path: ptr) -> i64 {
    strcpy(&FS_MK, path);
    let i: i64 = 1;
    while load8(&FS_MK + i) != 0 {
        if load8(&FS_MK + i) == 47 {
            store8(&FS_MK + i, 0);
            # 忽略已存在错误
            syscall(83, &FS_MK, 493, 0, 0, 0, 0);
            store8(&FS_MK + i, 47);
        }
        i = i + 1;
    }
    syscall(83, &FS_MK, 493, 0, 0, 0, 0);
    return 0;
}

# fs_rm(path)：unlink 文件（rmdir 目录交 unlinkat AT_REMOVEDIR 的 mo2x 适配）。
fn fs_rm(path: ptr) -> i64 {
    return syscall(87, path, 0, 0, 0, 0, 0);
}

fn list_dir(dir: ptr, names: i64, maxn: i64) -> i64 {
    # x86_64 open=2 O_RDONLY|O_DIRECTORY=0 -> getdents64 要求目录 fd
    let fd: i64 = syscall(2, dir, 0, 0, 0, 0);
    if fd < 0 { return 0 - 1; }
    let n: i64 = 0;
    let di: i64 = 0;
    DNAM_I = 0;
    while 1 {
        let r: i64 = syscall(217, fd, &DBUF, 4096, 0, 0, 0);
        if r <= 0 { break; }
        di = 0;
        while di < r {
            # linux_dirent64: ino(8) off(8) reclen(2) type(1) name...
            let reclen: i64 = DBUF[di + 16] + DBUF[di + 17] * 256;
            let nm: i64 = &DBUF + di + 19;
            # 跳过 . 和 ..
            if load8(nm) != 46 {
                if n < maxn {
                    let d: i64 = &DNAME + DNAM_I;
                    strcpy(d, nm);
                    DNAM_I = DNAM_I + strlen(nm) + 1;
                    store64(names + n * 8, d);
                    n = n + 1;
                }
            }
            di = di + reclen;
        }
    }
    syscall(3, fd, 0, 0, 0, 0, 0);
    return n;
}
