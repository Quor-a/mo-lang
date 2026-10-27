# kern64disk.mo —— ARM64 裸机上的**持久存储**：内核 + virtio-blk + 落盘文件系统
#
# mo-target: kern-aarch64   # 非原生后端，projcheck 跳过原生编译
#
#   bash tools/kernel64.sh examples/kern64disk.mo /tmp/modisk64.elf
#   python3 tools/kern64run.py /tmp/modisk64.elf --disk /tmp/disk.img
#   python3 tools/kern64run.py /tmp/modisk64.elf --disk /tmp/disk.img   # 第二次
#
# 与 examples/kern64sys.mo 的关系：那是 RAMFS（内存文件系统），**掉电即失**。
# 一个只能活在内存里的系统不是独立系统 —— 它连自己写的包都留不住。
# 这一份补上的是"重启之后还在不在"：
#
#   第一次启动（空盘）  探测 virtio-blk → 发现空盘 → 格式化 → 写文件 → 落盘
#   第二次启动（同一盘）探测 → 读到上次的超级块 → 挂载 → 读回上次写的内容
#
# 判据因此不是"写成功"，而是**两次独立启动之间数据还在**：
# 磁盘镜像是一个真文件，两次运行之间它没有被重置。
#
# 驱动按 virtio 1.0 的 MMIO 传输层规范写（magic 'virt' / version 2 /
# device id 2 / 描述符链 + avail/used 环），不是和模拟器约好的私有协议。
#
# 没有 libc、没有系统调用、没有宿主 OS —— 只有 MMIO。


var SECBUF: [512] byte = 0;
var REQ: [32] byte = 0;
var STB: [8] byte = 0;
var DESC: [128] byte = 0;      # 8 × 16 字节描述符
var AVAIL: [64] byte = 0;
var USED: [128] byte = 0;

var LASTUSED: i64 = 0;
var NSEC: i64 = 0;
var NFILE: i64 = 0;
var NWRITE: i64 = 0;
var OK: i64 = 0;

# ---------------------------------------------------------------- 字节序工具
# 墨语言只有 load8 / load64 / store8 / store64，没有 16/32 位原语。
# 设备寄存器是 32 位的，所以自己按小端拼装。这几个函数看似琐碎，
# 却是整条链的地基：拼错一个字节，magic 就对不上，而"对不上"和
# "没有设备"看起来完全一样。
fn put32(a: i64, v: i64) -> i64 {
    store8(a, v & 255);
    store8(a + 1, (v / 256) & 255);
    store8(a + 2, (v / 65536) & 255);
    store8(a + 3, (v / 16777216) & 255);
    return 0;
}

fn put16(a: i64, v: i64) -> i64 {
    store8(a, v & 255);
    store8(a + 1, (v / 256) & 255);
    return 0;
}

fn get16(a: i64) -> i64 {
    return load8(a) + load8(a + 1) * 256;
}

fn put64(a: i64, v: i64) -> i64 {
    store64(a, v);
    return 0;
}

fn get32(a: i64) -> i64 {
    return load8(a) + load8(a + 1) * 256 + load8(a + 2) * 65536
         + load8(a + 3) * 16777216;
}

fn mmio_rd(off: i64) -> i64 {
    return get32(167772160 + off);
}

fn mmio_wr(off: i64, v: i64) -> i64 {
    put32(167772160 + off, v);
    return 0;
}

# ---------------------------------------------------------------- 内容校验
# 读回来的内容用"长度 + 字节和"来判，而不是逐字节比对字符串常量：
# 后者需要一个可写的期望缓冲，前者只需要两个数字。
# "MO-DISK-OK" = 77 79 45 68 73 83 75 45 79 75 → 和 699，长 10。
fn csum(a: i64) -> i64 {
    let i: i64 = 0;
    let s: i64 = 0;
    while load8(a + i) != 0 {
        s = s + load8(a + i);
        i = i + 1;
    }
    return s;
}

fn slen(a: i64) -> i64 {
    let i: i64 = 0;
    while load8(a + i) != 0 { i = i + 1; }
    return i;
}

# ---------------------------------------------------------------- 块设备驱动
# virtio-mmio 初始化序列（规范 4.2.3）：
#   0 → ACKNOWLEDGE(1) → DRIVER(2) → 协商 features → FEATURES_OK(8)
#     → DRIVER_OK(4)，全程**每一步都要检查**，否则就是"跑起来了但设备没起来"。
fn blk_init() -> i64 {
    if mmio_rd(0) != 1953655158 { return -1; }    # 'virt' = 1953655158
    if mmio_rd(4) != 2 { return -2; }             # version
    if mmio_rd(8) != 2 { return -3; }             # device id = block

    mmio_wr(112, 0);            # status: reset
    mmio_wr(112, 1);            # ACKNOWLEDGE
    mmio_wr(112, 3);            # + DRIVER
    mmio_wr(32, 0);            # driver features = 0（不协商）
    mmio_wr(112, 11);           # + FEATURES_OK
    mmio_wr(112, 15);           # + DRIVER_OK

    mmio_wr(48, 0);            # queue select 0
    mmio_wr(56, 8);            # queue size 8
    # 地址必须先落到 i64 局部变量再传：墨语言的指针**不能**直接当 i64
    # 形参（后端生成 unsigned char*，传给 long long 形参会 -Wint-conversion）。
    let ad: i64 = &DESC;
    let aa: i64 = &AVAIL;
    let au: i64 = &USED;
    mmio_wr(128, ad);           # desc 低 32 位
    mmio_wr(132, 0);
    mmio_wr(144, aa);
    mmio_wr(148, 0);
    mmio_wr(160, au);
    mmio_wr(164, 0);
    mmio_wr(68, 1);            # queue ready

    NSEC = mmio_rd(256);
    return 0;
}

# 提交一次块请求：type 0=读 1=写
# 描述符链固定三节：请求头(16B) → 数据(512B) → 状态(1B)。
# 数据描述符的 WRITE 位是**方向**：读盘时设备写、写盘时设备读。
# 弄反了不会报错 —— 设备会往请求头里塞数据，症状是"读到的全是 0"。
fn blk_io(sector: i64, wr: i64) -> i64 {
    # 四个缓冲的地址都先落到 i64 局部变量：墨语言的指针不能直接进 i64
    # 形参（C 系后端会 -Wint-conversion）。
    let d0: i64 = &DESC;
    let pr: i64 = &REQ;
    let pb: i64 = &SECBUF;
    let ps: i64 = &STB;
    let aa: i64 = &AVAIL;
    let au: i64 = &USED;

    put64(d0, pr);               put32(d0 + 8, 16);
    put16(d0 + 12, 1);           put16(d0 + 14, 1);

    put64(d0 + 16, pb);          put32(d0 + 24, 512);
    if wr == 1 { put16(d0 + 28, 1); }
    else { put16(d0 + 28, 3); }
    put16(d0 + 30, 2);

    put64(d0 + 32, ps);          put32(d0 + 40, 1);
    put16(d0 + 44, 2);           put16(d0 + 46, 0);

    put32(pr, wr);
    put32(pr + 4, 0);
    put64(pr + 8, sector);
    store8(ps, 255);

    let idx: i64 = get16(aa + 2);
    put16(aa + 4 + (idx - (idx / 8) * 8) * 2, 0);
    put16(aa + 2, idx + 1);
    mmio_wr(80, 0);              # queue notify

    # 等 used 环。**必须**等：不等的话请求其实还没完成，
    # 读到的是上一次请求的残留 —— 不报错，只是数据不对。
    let n: i64 = 0;
    let done: i64 = 0;
    while n < 5000 {
        if done == 0 {
            if get16(au + 2) != LASTUSED {
                LASTUSED = get16(au + 2);
                done = 1;
            }
        }
        n = n + 1;
    }
    if done == 0 { return -9; }
    return load8(ps);
}





# ---------------------------------------------------------------- 内容校验
# 读回来的内容用"长度 + 字节和"来判，而不是逐字节比对字符串常量：
# 后者需要一个可写的期望缓冲，前者只需要两个数字。
# "MO-DISK-OK" = 77 79 45 68 73 83 75 45 79 75 → 和 699，长 10。


# ---------------------------------------------------------------- 块设备驱动
# virtio-mmio 初始化序列（规范 4.2.3）：
#   0 → ACKNOWLEDGE(1) → DRIVER(2) → 协商 features → FEATURES_OK(8)
#     → DRIVER_OK(4)，全程**每一步都要检查**，否则就是"跑起来了但设备没起来"。

# 提交一次块请求：type 0=读 1=写
# 描述符链固定三节：请求头(16B) → 数据(512B) → 状态(1B)。
# 数据描述符的 WRITE 位是**方向**：读盘时设备写、写盘时设备读。
# 弄反了不会报错 —— 设备会往请求头里塞数据，症状是"读到的全是 0"。

fn rdsec(s: i64) -> i64 { return blk_io(s, 0); }
fn wrsec(s: i64) -> i64 {
    NWRITE = NWRITE + 1;
    return blk_io(s, 1);
}

# ---------------------------------------------------------------- 文件系统
# 扇区布局（512 字节/扇区）：
#   0         超级块：0..3 = "MOFS1"，8..15 = 文件数
#   1         文件表：8 × 32 字节（名字 16 + 长度 8 + 数据扇区 8）
#   16..      数据区
fn sb_ok() -> i64 {
    if load8(&SECBUF) != 77 { return 0; }
    if load8(&SECBUF + 1) != 79 { return 0; }
    if load8(&SECBUF + 2) != 70 { return 0; }
    if load8(&SECBUF + 3) != 83 { return 0; }
    if load8(&SECBUF + 4) != 49 { return 0; }
    return 1;
}

fn clear_buf() -> i64 {
    let i: i64 = 0;
    while i < 512 { store8(&SECBUF + i, 0); i = i + 1; }
    return 0;
}

fn put_name(a: i64) -> i64 {
    store8(a, 104);      # h
    store8(a + 1, 105);  # i
    store8(a + 2, 0);
    return 0;
}

fn put_body(a: i64) -> i64 {
    store8(a, 77);       # M
    store8(a + 1, 79);   # O
    store8(a + 2, 45);   # -
    store8(a + 3, 68);   # D
    store8(a + 4, 73);   # I
    store8(a + 5, 83);   # S
    store8(a + 6, 75);   # K
    store8(a + 7, 45);   # -
    store8(a + 8, 79);   # O
    store8(a + 9, 75);   # K
    store8(a + 10, 0);
    return 0;
}

fn fmt() -> i64 {
    let sb: i64 = &SECBUF;
    clear_buf();
    store8(&SECBUF, 77);
    store8(&SECBUF + 1, 79);
    store8(&SECBUF + 2, 70);
    store8(&SECBUF + 3, 83);
    store8(&SECBUF + 4, 49);
    put64(sb + 8, 1);
    if wrsec(0) != 0 { return -1; }

    clear_buf();
    put_name(sb);
    put64(sb + 16, 10);
    put64(sb + 24, 16);
    if wrsec(1) != 0 { return -2; }

    clear_buf();
    put_body(sb);
    if wrsec(16) != 0 { return -3; }
    return 0;
}

fn show_body() -> i64 {
    let sb: i64 = &SECBUF;
    print(&SECBUF);
    print("\n len=");
    print_i64(slen(sb));
    print(" sum=");
    print_i64(csum(sb));
    if slen(sb) == 10 {
        if csum(sb) == 699 {
            print(" match=1\n");
            return 1;
        }
    }
    print(" match=0\n");
    return 0;
}

fn main() -> i64 {
    print("\nMO-KERN64-DISK BOOT\n");
    print("arch=aarch64  console=mmio-uart@150994944\n");
    print("no libc / no syscall / no host os\n");
    print("virtio-blk + persistent fs\n");

    let r: i64 = blk_init();
    if r != 0 {
        print("virtio-blk: not found err=");
        print_i64(r);
        print("\n");
        print("MO-KERN64-DISK HALT\n");
        return 0;
    }
    print("virtio-blk: magic=ok ver=2 dev=2 cap=");
    print_i64(NSEC);
    print("\n");

    if rdsec(0) != 0 {
        print("read err\n");
        print("MO-KERN64-DISK HALT\n");
        return 1;
    }

    if sb_ok() == 1 {
        let sb0: i64 = &SECBUF;
        NFILE = load64(sb0 + 8);
        print("mount: nfiles=");
        print_i64(NFILE);
        print("\n");

        if rdsec(1) != 0 { print("table read err\n"); return 1; }
        let dsec: i64 = load64(sb0 + 24);
        clear_buf();
        if rdsec(dsec) != 0 { print("data read err\n"); return 1; }
        print("read hi -> ");
        OK = show_body();
    } else {
        print("mount: no superblock -> format\n");
        if fmt() != 0 { print("format err\n"); return 1; }
        print("format: writes=");
        print_i64(NWRITE);
        print("\n");

        clear_buf();
        if rdsec(16) != 0 { print("verify read err\n"); return 1; }
        print("wrote hi -> ");
        OK = show_body();
    }

    print("MO-KERN64-DISK HALT\n");
    return 0;
}
