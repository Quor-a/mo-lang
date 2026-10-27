#!/usr/bin/env python3
"""
armrun —— 在 CPU 模拟器里**真正执行**墨语言的 ARM64 原生程序

  python3 tools/armrun.py /tmp/andromo.arm64

背景：墨语言能把程序交叉编译成 ARM64（Android 原生，静态无 libc），
但本机是 x86-64，之前**从来没能执行过** —— 只验证到 ELF 机器类型正确。

Unicorn 能模拟 ARM64 CPU，但它不模拟操作系统。所以要在 svc #0 处
**自己实现 Linux 的 syscall 表**（AArch64 用 include/uapi/asm-generic/unistd.h）：

  调用号放 x8，参数放 x0-x5，返回值放 x0，错误时 x0 为负的 errno。

只需实现程序实际用到的那几个调用即可。

这样就真正回答了"交叉编译出来的 ARM64 程序能不能跑、算得对不对"。
"""
import struct, sys, argparse, os

# 依赖装在持久目录（见 tools/pyreq.sh）：沙盒会重置系统 site-packages，
# 直接 `pip install` 的包下一轮就没了。
_PLIBS = os.environ.get("MO_PYLIBS", "/data/workspace/pylibs")
if os.path.isdir(_PLIBS) and _PLIBS not in sys.path:
    sys.path.insert(0, _PLIBS)

try:
    from unicorn import *
    from unicorn.arm64_const import *
except ImportError:
    sys.stderr.write("""
缺少 unicorn，无法做 ARM64 运行时验证。

  安装： pip install unicorn
  或跑： bash tools/pyreq.sh unicorn
""")
    sys.exit(2)

# ---- AArch64 Linux 系统调用号（asm-generic/unistd.h）----
NR = dict(
    getpid=172, read=63, write=64, openat=56, close=57,
    lseek=62, mkdirat=34, newfstatat=79, faccessat=48,
    ftruncate=46, brk=214, munmap=215, mmap=222, mprotect=226,
    exit=93, exit_group=94, set_tid_address=96,
    unlink=1026, unlinkat=35, io_setup=0,
    # getdents64 是 **61**，不是 x86-64 的 217 —— mo2x 的翻译表此前写 217，
    # 在 ARM64 上 217 是 add_key。这里按 asm-generic 真值实现，
    # 于是「号错了」在模拟器里会表现成 -ENOSYS 而不是静默空目录。
    getdents64=61,
)

STACK_TOP  = 0x7fffff0000
STACK_SIZE = 0x100000
BRK_BASE   = 0x40000000      # 模拟的堆起点（brk）


def s64(v):
    """Unicorn 读出来的是无符号 64 位；AT_FDCWD(-100) 会读成 2^64-100。"""
    return v - (1 << 64) if v >= (1 << 63) else v


def map_page(uc, addr, size):
    """逐页映射（Unicorn 下部分重叠会整块失败）"""
    start = addr & ~0xFFF
    end = (addr + size + 0xFFF) & ~0xFFF
    p = start
    while p < end:
        try:
            uc.mem_map(p, 0x1000)
        except UcError:
            pass
        p += 0x1000


def load_elf64(path, uc):
    """加载 64 位 ELF（小端）的可加载段，返回入口"""
    d = open(path, 'rb').read()
    assert d[:4] == b'\x7fELF', "不是 ELF"
    # ELF e_ident[EI_DATA]: 1 = ELFDATA2LSB（小端），2 = ELFDATA2MSB（大端）。
    # 别想当然地以为 2 是小端 —— 我第一版就是这么错的，于是
    # AArch64 小端程序被判成"不是小端"，报了个离谱的错误。
    assert d[4] == 2, "不是 ELF64"
    assert d[5] == 1, "不是小端（EI_DATA=%d）" % d[5]
    mach = struct.unpack('<H', d[18:20])[0]
    assert mach == 183, "不是 AArch64（machine=0x%x）" % mach
    entry = struct.unpack('<Q', d[24:32])[0]
    phoff = struct.unpack('<Q', d[32:40])[0]
    phent = struct.unpack('<H', d[54:56])[0]
    phnum = struct.unpack('<H', d[56:58])[0]
    segs = []
    for i in range(phnum):
        o = phoff + i * phent
        p_type = struct.unpack('<I', d[o:o+4])[0]
        p_flags = struct.unpack('<I', d[o+4:o+8])[0]
        p_off = struct.unpack('<Q', d[o+8:o+16])[0]
        p_vaddr = struct.unpack('<Q', d[o+16:o+24])[0]
        p_filesz = struct.unpack('<Q', d[o+32:o+40])[0]
        p_memsz = struct.unpack('<Q', d[o+40:o+48])[0]
        if p_type != 1 or p_memsz == 0:
            continue
        map_page(uc, p_vaddr, p_memsz)
        uc.mem_write(p_vaddr, d[p_off:p_off+p_filesz])
        if p_memsz > p_filesz:
            uc.mem_write(p_vaddr + p_filesz, b'\x00' * (p_memsz - p_filesz))
        segs.append((hex(p_vaddr), p_memsz))
    return entry, segs


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('elf')
    ap.add_argument('args', nargs='*', help='传给程序的命令行参数')
    ap.add_argument('--steps', type=int, default=50000000)
    ap.add_argument('--dumpfs', action='store_true',
                    help='打印内存文件系统内容与 openat(dfd,...) 实参')
    # --preload guest=host：把宿主机文件**预先**放进内存文件系统。
    #   没有它，被验证的程序只能读自己刚写的文件，于是"ARM64 上的汇编器
    #   读 .s 源码"这类路径根本进不去；--extract 是它的反向。
    ap.add_argument('--preload', action='append', default=[], metavar='GUEST=HOST',
                    help='把宿主机文件预置到内存文件系统（可多次）')
    # --extract guest=host：把程序写出的文件**取回**宿主机。
    #   产出是二进制（ELF）时尤其关键 —— --dumpfs 打印的是 decode 后的文本，
    #   二进制会被替换字符吃掉，等于拿不到产物。
    ap.add_argument('--extract', action='append', default=[], metavar='GUEST=HOST',
                    help='把内存文件系统里的文件写回宿主机（可多次）')
    a = ap.parse_args()

    uc = Uc(UC_ARCH_ARM64, UC_MODE_LITTLE_ENDIAN)

    entry, segs = load_elf64(a.elf, uc)
    map_page(uc, STACK_TOP - STACK_SIZE, STACK_SIZE)
    print("入口点     : 0x%x" % entry)
    print("已加载段   : %s" % ", ".join("%s(%d B)" % s for s in segs))

    stdout = bytearray()
    exit_code = [0]
    halted = [False]
    brk_cur = [BRK_BASE]

    # 内存文件系统：让 ARM64 程序真的能 open → write → lseek → read → close。
    # 没有它，openat 只能固定返回 -ENOENT，
    # 于是"文件 IO 通了"这句话根本无从验证 —— 只能验证"号没发错"。
    FS_DATA = {}      # path -> bytearray
    # 预置输入文件：读失败必须**响亮报错**。静默跳过的话，后面"读不到"会
    # 表现成程序自己报的错，看着像被测程序的 bug，实际是验证脚本没喂进去。
    for spec in a.preload:
        if '=' not in spec:
            sys.stderr.write("--preload 需要 GUEST=HOST 形式：%s\n" % spec); return 2
        g, h = spec.split('=', 1)
        try:
            FS_DATA[g] = bytearray(open(h, 'rb').read())
        except OSError as e:
            sys.stderr.write("--preload 读不到宿主机文件 %s：%s\n" % (h, e)); return 2
    FS_OPEN = {}      # fd   -> [path, offset]
    fs_next = [3]     # 0/1/2 = stdin/stdout/stderr
    fs_log = []       # [(dfd, path, flags)] —— 用于断言 dfd 确实是 AT_FDCWD

    def rd_str(uc, addr):
        out = bytearray()
        while len(out) < 4096:
            b = bytes(uc.mem_read(addr + len(out), 1))[0]
            if b == 0:
                break
            out.append(b)
        return out.decode('utf-8', 'replace')

    def handle(uc, intno, ud):
        nr = uc.reg_read(UC_ARM64_REG_X8)
        x0 = uc.reg_read(UC_ARM64_REG_X0)
        x1 = uc.reg_read(UC_ARM64_REG_X1)
        x2 = uc.reg_read(UC_ARM64_REG_X2)

        if nr == NR['write']:
            # write(fd, buf, count) —— fd 1/2 走 stdout，文件 fd 走内存文件系统
            cnt = s64(x2)
            # count 为负（常见于前一步 read/open 失败后直接把它当长度传下来）
            # 必须拦掉，否则 mem_read 拿到天文数字，模拟器自己先崩
            if cnt < 0 or cnt > (1 << 30):
                uc.reg_write(UC_ARM64_REG_X0, -14)    # -EFAULT
                return
            data = bytes(uc.mem_read(x1, cnt))
            x2 = cnt
            if x0 in FS_OPEN:
                ent = FS_OPEN[x0]
                buf = FS_DATA.setdefault(ent[0], bytearray())
                if ent[1] < len(buf):
                    buf[ent[1]:ent[1] + len(data)] = data
                else:
                    buf.extend(data)
                ent[1] = ent[1] + len(data)
                uc.reg_write(UC_ARM64_REG_X0, len(data))
                return
            if x0 == 1 or x0 == 2:
                if data:
                    stdout.extend(data)
                uc.reg_write(UC_ARM64_REG_X0, x2)
                return
            # 未打开的 fd 绝不能落到 stdout：那会让 open 失败的程序
            # 照样"打印出内容"，于是适配错误的变异被判成通过。
            uc.reg_write(UC_ARM64_REG_X0, -9)     # -EBADF
            return

        if nr in (NR['exit'], NR['exit_group']):
            exit_code[0] = x0 & 0xFF
            halted[0] = True
            uc.reg_write(UC_ARM64_REG_X0, 0)
            # 把 PC 挪到一个安全的死循环地址，让 emu_start 干净收尾
            uc.emu_stop()
            return

        if nr == NR['brk']:
            # brk(0) 返回当前断点；brk(addr) 扩展堆
            req = x0
            if req == 0 or req < brk_cur[0]:
                uc.reg_write(UC_ARM64_REG_X0, brk_cur[0])
                return
            need = req - brk_cur[0]
            map_page(uc, brk_cur[0], need)
            brk_cur[0] = req
            uc.reg_write(UC_ARM64_REG_X0, req)
            return

        if nr == NR['mmap']:
            # mmap(addr,len,prot,flags,fd,off) —— 这里只支持匿名映射
            length = x1
            fd = uc.reg_read(UC_ARM64_REG_X4)
            if length == 0:
                uc.reg_write(UC_ARM64_REG_X0, -22)   # -EINVAL
                return
            base = brk_cur[0] + 0x10000000
            base = (base + 0xFFF) & ~0xFFF
            map_page(uc, base, length)
            brk_cur[0] = base + length
            uc.reg_write(UC_ARM64_REG_X0, base)
            return

        if nr == NR['getpid']:
            uc.reg_write(UC_ARM64_REG_X0, 4242)
            return

        if nr == NR['set_tid_address']:
            uc.reg_write(UC_ARM64_REG_X0, 4242)
            return

        if nr == NR['read']:
            # 文件 fd：从内存文件系统读；其它（stdin）没有可用输入，返回 0 即 EOF
            if x0 in FS_OPEN:
                ent = FS_OPEN[x0]
                buf = FS_DATA.get(ent[0], bytearray())
                n = min(x2, max(0, len(buf) - ent[1]))
                if n > 0:
                    uc.mem_write(x1, bytes(buf[ent[1]:ent[1] + n]))
                ent[1] = ent[1] + n
                uc.reg_write(UC_ARM64_REG_X0, n)
                return
            if x0 == 0:
                uc.reg_write(UC_ARM64_REG_X0, 0)   # stdin：EOF
                return
            uc.reg_write(UC_ARM64_REG_X0, -9)      # -EBADF
            return

        if nr == NR['close']:
            if x0 in FS_OPEN:
                del FS_OPEN[x0]
            uc.reg_write(UC_ARM64_REG_X0, 0)
            return

        if nr == NR['lseek']:
            if x0 in FS_OPEN:
                ent = FS_OPEN[x0]
                off = s64(x1)
                buf = FS_DATA.get(ent[0], bytearray())
                if x2 == 0:
                    ent[1] = off
                elif x2 == 1:
                    ent[1] = ent[1] + off
                else:
                    ent[1] = len(buf) + off
                if ent[1] < 0:
                    ent[1] = 0
                uc.reg_write(UC_ARM64_REG_X0, ent[1])
                return
            uc.reg_write(UC_ARM64_REG_X0, -9)     # -EBADF
            return

        if nr == NR['mprotect']:
            uc.reg_write(UC_ARM64_REG_X0, 0)
            return

        if nr == NR['munmap']:
            uc.reg_write(UC_ARM64_REG_X0, 0)
            return

        if nr == NR['openat']:
            # openat(dfd, path, flags, mode)。dfd 必须是 AT_FDCWD(-100) ——
            # 它正是 mo2x 把 x86 的 open(2) 适配成 openat(56) 时插入的首参，
            # dfd 不对就说明适配错了。所以这里对非 AT_FDCWD 报 -EBADF，
            # 让"参数重排正确"成为可观测事实，而不是靠读生成代码推断。
            dfd = s64(x0)
            path = rd_str(uc, x1)
            flags = x2
            fs_log.append((dfd, path, flags))
            if dfd != -100:
                uc.reg_write(UC_ARM64_REG_X0, -9)     # -EBADF
                return
            if path in FS_DATA:
                if (flags & 0x200) != 0:              # O_TRUNC
                    FS_DATA[path] = bytearray()
            elif (path + "/") in FS_DATA:
                # 打开**目录**（O_DIRECTORY）——包管理器的 list 要先 open 再 getdents64。
                # 目录在内存 FS 里以 "xxx/" 为键，这里必须认，否则 list 恒得到 -ENOENT。
                pass
            else:
                if (flags & 0x40) == 0:               # 没有 O_CREAT
                    uc.reg_write(UC_ARM64_REG_X0, -2)  # -ENOENT
                    return
                FS_DATA[path] = bytearray()
            fd = fs_next[0]
            fs_next[0] = fd + 1
            FS_OPEN[fd] = [path, 0]
            uc.reg_write(UC_ARM64_REG_X0, fd)
            return

        if nr == NR['unlinkat']:
            dfd = s64(x0)
            path = rd_str(uc, x1)
            # unlinkat 也是 *at：dfd 一样要校验。此前只记录 openat/mkdirat，
            # 于是 unlinkat 与 newfstatat 的 dfd **从未被检查过** —— 正好是
            # 「重排漏了一个」最容易藏的地方。
            flags = x2
            fs_log.append((dfd, path, 0))
            if dfd != -100:
                uc.reg_write(UC_ARM64_REG_X0, -9)
                return
            # AT_REMOVEDIR = 0x200：删目录。模拟器里目录以 "path/" 为键。
            # 包管理器的 remove 要先删包内文件再删包目录，缺了这一支
            # remove 只能留下空目录 —— 不报错，但 list 会一直看到它。
            if (flags & 0x200) != 0:
                dk = path.rstrip('/') + '/'
                if dk in FS_DATA:
                    del FS_DATA[dk]
                    uc.reg_write(UC_ARM64_REG_X0, 0)
                else:
                    uc.reg_write(UC_ARM64_REG_X0, -2)
                return
            if path in FS_DATA:
                del FS_DATA[path]
                uc.reg_write(UC_ARM64_REG_X0, 0)
            else:
                uc.reg_write(UC_ARM64_REG_X0, -2)
            return

        if nr == NR['mkdirat']:
            dfd = s64(x0)
            path = rd_str(uc, x1)
            fs_log.append((dfd, path, 0))
            if dfd != -100:
                uc.reg_write(UC_ARM64_REG_X0, -9)
                return
            FS_DATA[path + "/"] = bytearray()
            uc.reg_write(UC_ARM64_REG_X0, 0)
            return

        if nr == NR['newfstatat']:
            dfd = s64(x0)
            path = rd_str(uc, x1)
            buf = x2
            fs_log.append((dfd, path, 0))
            if dfd != -100:
                uc.reg_write(UC_ARM64_REG_X0, -9)
                return
            if path in FS_DATA:
                n = len(FS_DATA[path])
            elif (path + "/") in FS_DATA:
                n = 0
            else:
                uc.reg_write(UC_ARM64_REG_X0, -2)   # -ENOENT
                return
            # st_size 在 struct stat 偏移 48（ARM64/asm-generic，小端）
            uc.mem_write(buf + 48, n.to_bytes(8, 'little'))
            uc.reg_write(UC_ARM64_REG_X0, 0)
            return

        if nr == NR['getdents64']:
            # getdents64(fd, buf, count) —— 让包管理器的 list 真的能列目录。
            # struct linux_dirent64（小端）：
            #   +0  d_ino(8)  +8  d_off(8)  +16 d_reclen(2)  +18 d_type(1)
            #   +19 d_name[]（NUL 结尾，reclen 向上对齐到 8）
            # 墨语言侧用 load8 逐字节解，所以布局必须和内核一致。
            if x0 not in FS_OPEN:
                uc.reg_write(UC_ARM64_REG_X0, -9)     # -EBADF
                return
            dirpath = FS_OPEN[x0][0].rstrip('/')
            prefix = dirpath + '/'
            names = []
            seen = set()
            for pth in FS_DATA:
                if not pth.startswith(prefix):
                    continue
                rest = pth[len(prefix):]
                if rest == '':
                    continue
                seg = rest.split('/')[0]
                if seg and seg not in seen:
                    seen.add(seg)
                    names.append(seg)
            # 真实 Linux 的 getdents64 **会**返回 "." 与 ".."。
            # 早先模拟器不返回它们，于是"忘记跳过点目录"这类错误在模拟器里
            # 永远抓不到 —— 模拟器和真机行为不一致本身就是隐患。
            names = ['.', '..'] + names
            off = 0
            for nm in sorted(names):
                nb = nm.encode('utf-8', 'replace')
                isdir = 4 if (prefix + nm + '/') in FS_DATA else 8
                reclen = 19 + len(nb) + 1
                reclen = (reclen + 7) & ~7
                if off + reclen > x2:
                    break
                ent = bytearray()
                ent += (1).to_bytes(8, 'little')          # d_ino
                ent += (off + reclen).to_bytes(8, 'little')  # d_off
                ent += reclen.to_bytes(2, 'little')        # d_reclen
                ent += bytes([isdir])                      # d_type
                ent += nb + b'\x00'
                ent += b'\x00' * (reclen - len(ent))
                uc.mem_write(x1 + off, bytes(ent))
                off += reclen
            uc.reg_write(UC_ARM64_REG_X0, off)
            return

        if nr == NR['ftruncate']:
            uc.reg_write(UC_ARM64_REG_X0, 0)
            return

        # 未实现的调用：明确报出来，而不是静默返回 0
        sys.stderr.write("[armrun] 未实现的系统调用 %d（x0=%d）\n" % (nr, x0))
        uc.reg_write(UC_ARM64_REG_X0, -38)        # -ENOSYS

    # svc #0 在 Unicorn 里表现为中断（UC_HOOK_INTR）
    uc.hook_add(UC_HOOK_INTR, handle)

    # 布置 Linux 初始栈：[sp]=argc, [sp+8]=argv[0], ..., NULL, envp NULL,
    # 然后 auxv(AT_NULL)。墨语言的 _start 就是按这个布局读的。
    argv_list = [a.elf] + list(a.args)
    sp = (STACK_TOP - 0x100) & ~0xF
    # 先把字符串写进去
    str_addrs = []
    cur = sp + (len(argv_list) + 4) * 8
    for arg in argv_list:
        b = arg.encode() + b'\x00'
        uc.mem_write(cur, b)
        str_addrs.append(cur)
        cur += (len(b) + 7) & ~7
    uc.mem_write(sp, struct.pack('<Q', len(argv_list)))
    for i, addr in enumerate(str_addrs):
        uc.mem_write(sp + 8 + i * 8, struct.pack('<Q', addr))
    uc.mem_write(sp + 8 + len(argv_list) * 8, struct.pack('<Q', 0))   # argv NULL
    uc.mem_write(sp + 8 + (len(argv_list)+1) * 8, struct.pack('<Q', 0))  # envp NULL
    uc.mem_write(sp + 8 + (len(argv_list)+2) * 8, struct.pack('<Q', 0))  # auxv AT_NULL
    uc.mem_write(sp + 8 + (len(argv_list)+3) * 8, struct.pack('<Q', 0))
    uc.reg_write(UC_ARM64_REG_SP, sp)

    print("开始执行（上限 %d 条指令）..." % a.steps)
    import time
    t0 = time.time()
    try:
        uc.emu_start(entry, 0, count=a.steps, timeout=300_000_000)
    except UcError as e:
        print("执行停止   : %s" % e)
        print("停止时 PC  : 0x%x" % uc.reg_read(UC_ARM64_REG_PC))
        print("停止时 X8  : %d" % uc.reg_read(UC_ARM64_REG_X8))
    if not halted[0]:
        print("（未走到 exit：PC=0x%x，可能是指令上限或执行异常）"
              % uc.reg_read(UC_ARM64_REG_PC))
    dt = time.time() - t0

    text = stdout.decode('utf-8', 'replace')
    print()
    print("========== ARM64 程序输出 ==========")
    print(text if text else "（空 —— 程序什么都没输出）")
    print("====================================")
    print("退出码     : %d" % exit_code[0])
    print("耗时       : %.2f 秒" % dt)
    for spec in a.extract:
        if '=' not in spec:
            sys.stderr.write("--extract 需要 GUEST=HOST 形式：%s\n" % spec); return 2
        g, h = spec.split('=', 1)
        if g not in FS_DATA:
            sys.stderr.write("--extract：内存 FS 里没有 %s（程序没写出来）\n" % g)
            return 2
        try:
            open(h, 'wb').write(bytes(FS_DATA[g]))
        except OSError as e:
            sys.stderr.write("--extract 写不到 %s：%s\n" % (h, e)); return 2
        print("取出文件   : %s -> %s (%d 字节)" % (g, h, len(FS_DATA[g])))

    if a.dumpfs:
        print("openat/mkdirat 调用 : %d" % len(fs_log))
        for (dfd, path, flags) in fs_log:
            print("  dfd=%d path=%s flags=%d" % (dfd, path, flags))
        print("内存文件系统内容：")
        for p in sorted(FS_DATA.keys()):
            print("  %s = %r" % (p, bytes(FS_DATA[p]).decode('utf-8', 'replace')))
    return 0 if text else 1


if __name__ == '__main__':
    sys.exit(main())
