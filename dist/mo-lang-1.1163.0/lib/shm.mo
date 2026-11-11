# shm —— 共享内存与 mmap（用墨语言自己写的）
#
# 为什么需要它：进程池（proc.mo）的任务与结果只能是 i64，
# 管道一次只收发 8 字节。要传数组/字符串/结构体，就得有共享内存。
#
# 本库提供：
#   1. mmap / munmap / mprotect —— 通用内存映射
#   2. shm_open / shm_unlink —— POSIX 命名共享内存
#   3. shm_alloc —— 匿名共享映射（fork 后父子共享，最常用）
#   4. **shm 数组**：在共享内存里放一个 i64 数组，多进程直接读写
#
# 全部是系统调用，不依赖 libc。
#
# 关键前提：MAP_SHARED|MAP_ANONYMOUS 的映射在 fork 之后
# **父子共享同一块物理页**（MAP_PRIVATE 则是写时复制，不共享）。
# 所以 shm_alloc 必须同时带这两个标志，少一个就退化成私有内存，
# 表现为"子进程写了父进程看不到"——不报错，只是结果不对。
import "err.mo";
import "io.mo";
import "str.mo";

# ---------------------------------------------------------------- 常量

var MMAP_PROT_READ:  i64 = 1;
var MMAP_PROT_WRITE: i64 = 2;
var MMAP_MAP_SHARED: i64 = 1;
var MMAP_MAP_PRIVATE: i64 = 2;
var MMAP_MAP_ANON:   i64 = 32;      # MAP_ANONYMOUS
var MMAP_MAP_FIXED:  i64 = 16;

# ---------------------------------------------------------------- mmap

# mmap(9)：addr, len, prot, flags, fd, off
fn mmap(addr: i64, len: i64, prot: i64, flags: i64, fd: i64, off: i64) -> i64 {
    return syscall(9, addr, len, prot, flags, fd, off);
}
fn munmap(addr: i64, len: i64) -> i64 {
    return syscall(11, addr, len, 0, 0, 0, 0);
}
fn mprotect(addr: i64, len: i64, prot: i64) -> i64 {
    return syscall(10, addr, len, prot, 0, 0, 0);
}

# msync(26)：把映射的改动刷回文件（对 shm_open 的文件后端有意义）
fn msync(addr: i64, len: i64, flags: i64) -> i64 {
    return syscall(26, addr, len, flags, 0, 0, 0);
}

# ---------------------------------------------------------------- 共享分配

# 匿名共享映射：fork 后父子进程共享。
# 返回映射地址；失败返回负的 errno（裸系统调用不返回 -1 + errno）。
fn shm_alloc(nbytes: i64) -> i64 {
    let a: i64 = mmap(0, nbytes, 3, 33, 0 - 1, 0);   # RW, SHARED|ANON
    if a < 0 { err_set(E_NOMEM, "mmap failed", "shm_alloc"); }
    return a;
}

fn shm_free(addr: i64, nbytes: i64) -> i64 {
    return munmap(addr, nbytes);
}

# ---------------------------------------------------------------- POSIX shm

# shm_open：在 /dev/shm 下建文件再 mmap。
# 为什么不用 SYS_shm_open：Linux 没有这个系统调用号（glibc 是用
# open("/dev/shm/xxx") + mmap 实现的），所以照做即可。
var SHM_PATH: [256] byte = 0;

fn shm_open(name: i64, nbytes: i64) -> i64 {
    strcpy(&SHM_PATH, "/dev/shm/");
    strcat(&SHM_PATH, name);
    # O_RDWR|O_CREAT = 2|64 = 66，模式 0600
    let fd: i64 = syscall(2, &SHM_PATH, 66, 384, 0, 0);
    if fd < 0 { err_set(E_IO, "shm_open failed", "shm_open"); return 0 - 1; }
    # 先 ftruncate(77) 把文件撑到需要的大小，否则 mmap 后访问会 SIGBUS
    let t: i64 = syscall(77, fd, nbytes, 0, 0, 0, 0);
    if t < 0 {
        let c: i64 = syscall(3, fd, 0, 0, 0, 0, 0);
        err_set(E_IO, "ftruncate failed", "shm_open");
        return 0 - 1;
    }
    let a: i64 = mmap(0, nbytes, 3, 1, fd, 0);       # RW, SHARED
    let c2: i64 = syscall(3, fd, 0, 0, 0, 0, 0);     # 映射完就可以关 fd
    if a < 0 { err_set(E_NOMEM, "mmap failed", "shm_open"); }
    return a;
}

fn shm_unlink(name: i64) -> i64 {
    strcpy(&SHM_PATH, "/dev/shm/");
    strcat(&SHM_PATH, name);
    return syscall(87, &SHM_PATH, 0, 0, 0, 0);    # unlink
}

# ---------------------------------------------------------------- 共享数组
#
# 布局：[0]=容量  [1..n]=元素
# 这样"数组"自带长度，进程间不用另外同步容量。

fn shm_array_new(n: i64) -> i64 {
    let a: i64 = shm_alloc((n + 1) * 8);
    if a < 0 { return a; }
    shm_array_zero(a);
    store64(a, n);
    return a;
}

# 只清元素，**不动** [0] 的容量。
#
# 第一版把 [0] 也清了 —— 那等于把"容量"抹成 0，之后所有 set/add
# 都判定越界并返回失败，数组看起来"能写但永远是 0"。
# 不报错、不崩溃，只是结果不对，正是最难查的那类。
# 而且它只在"先 new 再 zero"时才会暴露（new 之后 [0] 才有值）。
fn shm_array_zero(a: i64) -> i64 {
    let n: i64 = load64(a);
    let i: i64 = 1;
    while i <= n {
        store64(a + i * 8, 0);
        i = i + 1;
    }
    return 0;
}

fn shm_array_len(a: i64) -> i64 { return load64(a); }

fn shm_array_get(a: i64, i: i64) -> i64 {
    let n: i64 = load64(a);
    if i < 0 { err_set(E_RANGE, "index < 0", "shm_array_get"); return 0; }
    if i >= n { err_set(E_RANGE, "index >= len", "shm_array_get"); return 0; }
    return load64(a + (i + 1) * 8);
}

fn shm_array_set(a: i64, i: i64, v: i64) -> i64 {
    let n: i64 = load64(a);
    if i < 0 { err_set(E_RANGE, "index < 0", "shm_array_set"); return 0 - 1; }
    if i >= n { err_set(E_RANGE, "index >= len", "shm_array_set"); return 0 - 1; }
    store64(a + (i + 1) * 8, v);
    return 0;
}

# 就地累加（多进程各自累加自己的部分，无需返回值）
fn shm_array_add(a: i64, i: i64, v: i64) -> i64 {
    let n: i64 = load64(a);
    if i < 0 { return 0 - 1; }
    if i >= n { return 0 - 1; }
    let o: i64 = a + (i + 1) * 8;
    store64(o, load64(o) + v);
    return 0;
}

fn shm_array_sum(a: i64) -> i64 {
    let n: i64 = load64(a);
    let s: i64 = 0;
    let i: i64 = 0;
    while i < n {
        s = s + load64(a + (i + 1) * 8);
        i = i + 1;
    }
    return s;
}

fn shm_array_free(a: i64) -> i64 {
    let n: i64 = load64(a);
    return munmap(a, (n + 1) * 8);
}

# ---------------------------------------------------------------- 共享字节缓冲

# 在共享内存里放字符串：布局 [0..7]=容量, [8..]=字节
fn shm_buf_new(nbytes: i64) -> i64 {
    let a: i64 = shm_alloc(nbytes + 8);
    if a < 0 { return a; }
    store64(a, nbytes);
    store8(a + 8, 0);
    return a;
}

fn shm_buf_set(a: i64, s: i64) -> i64 {
    let cap: i64 = load64(a);
    let i: i64 = 0;
    while load8(s + i) != 0 {
        if i >= cap - 1 { break; }
        store8(a + 8 + i, load8(s + i));
        i = i + 1;
    }
    store8(a + 8 + i, 0);
    return i;
}

fn shm_buf_get(a: i64) -> i64 { return a + 8; }
fn shm_buf_cap(a: i64) -> i64 { return load64(a); }
fn shm_buf_free(a: i64) -> i64 { return munmap(a, load64(a) + 8); }
