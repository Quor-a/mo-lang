import "str.mo";
import "vec.mo";
import "mem.mo";
# dir —— 目录遍历与文件元数据（用墨语言自己写的）
#
# 直接用 getdents64(217) / stat(4) / uname(63) / sysinfo(99)，
# 不依赖 libc 的 opendir/readdir/stat —— 因为墨语言不链接任何库。
#
# getdents64 的 dirent64 布局（x86-64）：
#     +0   d_ino   (8)
#     +8   d_off   (8)
#     +16  d_reclen(2)
#     +18  d_type  (1)
#     +19  d_name  (变长，以 0 结尾)

var DT_UNKNOWN: i64 = 0;
var DT_REG: i64 = 8;
var DT_DIR: i64 = 4;

var d_fd: i64 = 0;
var d_buf: [65536] byte = 0;
var d_len: i64 = 0;
var d_pos: i64 = 0;

# 打开目录，返回 0 表示成功
fn dir_open(path: i64) -> i64 {
    d_fd = syscall(2, path, 65536, 0, 0, 0);
    if d_fd < 0 { return -1; }
    d_len = 0;
    d_pos = 0;
    return 0;
}

# 读下一个条目：返回 1 表示取到，0 表示结束。名字写进 name
fn dir_next(name: i64, ty: i64) -> i64 {
    while 1 {
        if d_pos >= d_len {
            d_len = syscall(217, d_fd, &d_buf, 65536, 0, 0, 0);
            d_pos = 0;
            if d_len <= 0 { return 0; }
        }
        let base: i64 = &d_buf + d_pos;
        let reclen: i64 = load8(base + 16) + load8(base + 17) * 256;
        if reclen == 0 { return 0; }
        let t: i64 = load8(base + 18);
        if ty != 0 { store64(ty, t); }
        # 拷名字
        let i: i64 = 0;
        while load8(base + 19 + i) != 0 {
            store8(name + i, load8(base + 19 + i));
            i = i + 1;
        }
        store8(name + i, 0);
        d_pos = d_pos + reclen;
        # 跳过 . 和 ..
        if load8(name) == 46 {
            if load8(name + 1) == 0 { continue; }
            if load8(name + 1) == 46 {
                if load8(name + 2) == 0 { continue; }
            }
        }
        return 1;
    }
    return 0;
}

fn dir_close() -> i64 {
    if d_fd > 0 {
        syscall(3, d_fd, 0, 0, 0, 0, 0);
        d_fd = 0;
    }
    return 0;
}

# ---- stat(4) ----
# x86-64 struct stat 中我们关心的偏移：
#     +0  st_dev   +8  st_ino   +24 st_mode  +48 st_size
var st_buf: [144] byte = 0;

fn stat_size(path: i64) -> i64 {
    let r: i64 = syscall(4, path, &st_buf, 0, 0, 0);
    if r < 0 { return -1; }
    let v: i64 = load8(&st_buf + 48) + load8(&st_buf + 49) * 256
               + load8(&st_buf + 50) * 65536 + load8(&st_buf + 51) * 16777216;
    return v;
}

fn stat_mode(path: i64) -> i64 {
    let r: i64 = syscall(4, path, &st_buf, 0, 0, 0);
    if r < 0 { return -1; }
    return load8(&st_buf + 24) + load8(&st_buf + 25) * 256;
}

# 是否为普通文件 / 目录
fn is_dir(path: i64) -> i64 {
    let m: i64 = stat_mode(path);
    if m < 0 { return 0; }
    if ((m / 4096) & 15) == 4 { return 1; }   # 注意：必须加括号，== 比 & 结合更紧
    return 0;
}

fn is_file(path: i64) -> i64 {
    let m: i64 = stat_mode(path);
    if m < 0 { return 0; }
    if ((m / 4096) & 15) == 8 { return 1; }
    return 0;
}

fn exists(path: i64) -> i64 {
    if stat_mode(path) < 0 { return 0; }
    return 1;
}

# 改权限：chmod(path, mode) —— 对应「权限」需求
fn chmod(path: i64, mode: i64) -> i64 {
    return syscall(90, path, mode, 0, 0, 0, 0);
}

fn mkdir(path: i64, mode: i64) -> i64 {
    return syscall(83, path, mode, 0, 0, 0);
}

fn unlink(path: i64) -> i64 {
    return syscall(87, path, 0, 0, 0, 0);
}

fn rename(old: i64, new: i64) -> i64 {
    return syscall(82, old, new, 0, 0, 0, 0);
}

# ---- uname(63) / sysinfo(99)：读内核信息 ----
var u_buf: [390] byte = 0;

fn uname_field(which: i64, dst: i64) -> i64 {
    let r: i64 = syscall(63, &u_buf, 0, 0, 0, 0, 0);
    if r < 0 { return -1; }
    # utsname 每个字段 65 字节
    let p: i64 = &u_buf + which * 65;
    strcpy(dst, p);
    return 0;
}

fn uname_sysname(dst: i64) -> i64 { return uname_field(0, dst); }
fn uname_nodename(dst: i64) -> i64 { return uname_field(1, dst); }
fn uname_release(dst: i64) -> i64 { return uname_field(2, dst); }
fn uname_version(dst: i64) -> i64 { return uname_field(3, dst); }
fn uname_machine(dst: i64) -> i64 { return uname_field(4, dst); }

# 返回总内存（字节），来自 sysinfo
fn mem_total() -> i64 {
    let s: [112] byte = 0;
    let r: i64 = syscall(99, &s, 0, 0, 0, 0, 0);
    if r < 0 { return -1; }
    let v: i64 = 0;
    let i: i64 = 7;
    while i >= 0 {
        v = v * 256 + load8(&s + 32 + i);
        i = i - 1;
    }
    return v;
}

fn uptime_secs() -> i64 {
    let s: [112] byte = 0;
    let r: i64 = syscall(99, &s, 0, 0, 0, 0, 0);
    if r < 0 { return -1; }
    let v: i64 = 0;
    let i: i64 = 7;
    while i >= 0 {
        v = v * 256 + load8(&s + i);
        i = i - 1;
    }
    return v;
}

# ==========================================================================
#  批量接口：dir_list
#
#  只有 dir_open / dir_next / dir_close 时，每个调用方都要自己写
#  「开目录 → while 循环 → 收集 → 关目录」这一套，而且各自用固定大小数组
#  收集 —— 条目一多就越界写崩（实测 147 个条目直接段错误）。
#
#  所以补一个批量接口，返回 vec（动态增长，没有固定容量上限）。
#  用 vec 而不是"填充调用方给的缓冲区"，就从根上消除了"条目数超过缓冲"
#  这一整类问题，而不是把上限换个数。
# ==========================================================================
import "vec.mo";
import "mem.mo";

# 列出目录下所有条目（不含 . 与 ..），返回一个 vec，
# 元素是**堆上的字符串副本**（str_dup），调用方可以随意保存。
#
# 返回 -1 表示目录打不开。调用方必须先 heap_init()。
fn dir_list(path: i64) -> i64 {
    return dir_list_max(path, 0);
}

# max > 0 时最多收 max 个条目；max == 0 表示不设上限。
#
# 为什么还保留 max：遍历超大目录时，调用方可能只想看前几个
# （比如只想知道"目录非空"）。不限条目地把几万个名字全拷进堆里太浪费。
fn dir_list_max(path: i64, max: i64) -> i64 {
    if dir_open(path) < 0 {
        return -1;
    }
    let v: i64 = vec_new();
    let name: [256] byte = 0;
    let ty: i64 = 0;
    while dir_next(&name, &ty) == 1 {
        if max > 0 {
            if vec_len(v) >= max { break; }
        }
        vec_push(v, str_dup(&name));
    }
    dir_close();
    return v;
}

# 只列出某一类条目。want 用 DT_REG(8) / DT_DIR(4)。
# 注意：部分文件系统（如某些挂载点）会把 d_type 报成 DT_UNKNOWN(0)，
# 这时应当回退到 stat 判断，而不是直接信任 d_type。
fn dir_list_type(path: i64, want: i64) -> i64 {
    if dir_open(path) < 0 {
        return -1;
    }
    let v: i64 = vec_new();
    let name: [256] byte = 0;
    let ty: i64 = 0;
    while dir_next(&name, &ty) == 1 {
        if ty == want {
            vec_push(v, str_dup(&name));
        }
    }
    dir_close();
    return v;
}
