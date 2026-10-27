#!/usr/bin/env python3
"""
ppc64run —— 在 CPU 模拟器里**真正执行**墨语言的 ppc64（大端）原生程序

  python3 tools/ppc64run.py build/hello.ppc64

与 armrun.py / riscvrun.py 同一套思路，差异只有两处：

  ARM64:   svc #0，调用号 x8，参数 x0-x5
  RISC-V:  ecall，调用号 a7，参数 a0-a5
  s390x:   svc 0， 调用号 r1，参数 r2-r7，返回 r2

**s390x 是大端**，Unicorn 必须用 UC_MODE_BIG_ENDIAN，否则指令解码全错，
程序会立刻跑飞。

另外 s390x 用的是**它自己的**系统调用号表（不是 asm-generic）：
write=4、exit=1、brk=45、mmap=90 等，与 x86-64 完全不同。
"""
import struct, sys, argparse, os

# 依赖装在持久目录（见 tools/pyreq.sh）：沙盒会重置系统 site-packages，
# 直接 `pip install` 的包下一轮就没了。
_PLIBS = os.environ.get("MO_PYLIBS", "/data/workspace/pylibs")
if os.path.isdir(_PLIBS) and _PLIBS not in sys.path:
    sys.path.insert(0, _PLIBS)

try:
    from unicorn import *
    from unicorn.ppc_const import *
except ImportError:
    sys.stderr.write("""
缺少 unicorn，无法做 s390x 运行时验证。

  安装： pip install unicorn
  或跑： bash tools/pyreq.sh unicorn
""")
    sys.exit(2)

# ---- AArch64 Linux 系统调用号（asm-generic/unistd.h）----
# s390x 有**自己**的调用号表，不要复用 asm-generic 的那套
NR = dict(
    getpid=20, read=3, write=4, open=5, close=6,
    ftruncate=93, brk=45, munmap=73, mmap=90, mprotect=125,
    exit=1, exit_group=248, set_tid_address=252,
)

# s390x 下 Unicorn 只接受**低位**地址。
# 实测：栈放 0x18000 时 `lg` 读到正确值；放 0x3fffff00 时读到 0
# （不报错，只是内容错）。所以这里把整个布局都压到 1MB 以下。
# ARM64 / RISC-V 用高位地址没问题，只有 s390x 需要这样。
# 栈必须**避开代码段**。用 `--image-base=0x10000` 后代码落在 0x10000 起，
# 而默认栈布局（0x18000-0x8000）恰好覆盖 0x10000~0x18000，会把代码段
# 整个冲掉 —— 表现为第一条指令就触发陷入、PC 从不前进。
# 这里把栈抬到 0x60000，仍在 1MB 以下（Unicorn 只可靠访问低位）。
STACK_TOP  = 0x60000
STACK_SIZE = 0x8000
BRK_BASE   = 0x80000         # 模拟的堆起点（brk，同样压低且避开栈）


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
    # s390x 是**大端**（EI_DATA=2）。如果这里照抄小端断言，
    # 会直接把正确产物判成"不是小端"——1=LSB, 2=MSB。
    assert d[5] == 2, "不是大端（EI_DATA=%d）" % d[5]
    mach = struct.unpack('>H', d[18:20])[0]
    assert mach == 21, "不是 ppc64le（machine=0x%x）" % mach
    entry = struct.unpack('>Q', d[24:32])[0]
    phoff = struct.unpack('>Q', d[32:40])[0]
    phent = struct.unpack('>H', d[54:56])[0]
    phnum = struct.unpack('>H', d[56:58])[0]
    segs = []
    for i in range(phnum):
        o = phoff + i * phent
        p_type = struct.unpack('>I', d[o:o+4])[0]
        p_flags = struct.unpack('>I', d[o+4:o+8])[0]
        p_off = struct.unpack('>Q', d[o+8:o+16])[0]
        p_vaddr = struct.unpack('>Q', d[o+16:o+24])[0]
        p_filesz = struct.unpack('>Q', d[o+32:o+40])[0]
        p_memsz = struct.unpack('>Q', d[o+40:o+48])[0]
        if p_type != 1 or p_memsz == 0:
            continue
        map_page(uc, p_vaddr, p_memsz)
        uc.mem_write(p_vaddr, d[p_off:p_off+p_filesz])
        if p_memsz > p_filesz:
            uc.mem_write(p_vaddr + p_filesz, b'\x00' * (p_memsz - p_filesz))
        segs.append((hex(p_vaddr), p_memsz))
    return entry, segs


def find_toc_base(path):
    """找 TOC 基址：优先 .toc 节，静态链接后通常只剩 .got。"""
    d = open(path, 'rb').read()
    if d[:4] != b'\x7fELF':
        return 0
    shoff = struct.unpack('>Q', d[40:48])[0]
    shent = struct.unpack('>H', d[58:60])[0]
    shnum = struct.unpack('>H', d[60:62])[0]
    shstrndx = struct.unpack('>H', d[62:64])[0]
    if shoff == 0 or shnum == 0:
        return 0
    stro = struct.unpack('>Q', d[shoff + shstrndx*shent + 24:shoff + shstrndx*shent + 32])[0]

    def nm(x):
        e = d.index(b'\0', stro + x)
        return d[stro+x:e].decode()
    got = 0
    for i in range(shnum):
        o = shoff + i*shent
        name = nm(struct.unpack('>I', d[o:o+4])[0])
        addr = struct.unpack('>Q', d[o+16:o+24])[0]
        if name == '.toc':
            return addr
        if name == '.got':
            got = addr
    return got


def main():
    sys.stderr.write("""
ppc64run: Unicorn 的 PPC64 后端不支持无条件分支指令 `b`。

  孤立实验：在 0x1000 放 `b 0x1100` 后单步执行，
  抛 UcError: Unhandled CPU exception，PC 仅前进 4（被当作 nop）。
  前跳 / 后跳 / 设置 MSR 的 IR·DR 位，三种情况都失败。

  而 `addi` + `sc` 这类直线指令能正常执行 —— 所以不是墨语言产物的问题，
  是 Unicorn 的实现不完整。任何真实程序都要用分支，因此
  PowerPC 无法用 Unicorn 做运行时验证。

  需要真执行请用 qemu-ppc64 / qemu-system-ppc64。
""")
    return 2

    ap = argparse.ArgumentParser()
    ap.add_argument('elf')
    ap.add_argument('args', nargs='*', help='传给程序的命令行参数')
    ap.add_argument('--steps', type=int, default=50000000)
    a = ap.parse_args()

    uc = Uc(UC_ARCH_PPC, UC_MODE_PPC64 | UC_MODE_BIG_ENDIAN)

    entry, segs = load_elf64(a.elf, uc)
    map_page(uc, STACK_TOP - STACK_SIZE, STACK_SIZE)
    print("入口点     : 0x%x" % entry)
    print("已加载段   : %s" % ", ".join("%s(%d B)" % s for s in segs))

    stdout = bytearray()
    exit_code = [0]
    halted = [False]
    brk_cur = [BRK_BASE]

    def handle(uc, intno, ud):
        nr = uc.reg_read(UC_PPC_REG_0)
        x0 = uc.reg_read(UC_PPC_REG_3)
        x1 = uc.reg_read(UC_PPC_REG_4)
        x2 = uc.reg_read(UC_PPC_REG_5)

        if nr == NR['write']:
            data = bytes(uc.mem_read(x1, x2))
            # 收敛保护：s390x 下 exit 之后 Unicorn 仍会继续取指，
            # 程序会再跑一轮（表现为输出重复）。检测到输出开始重复
            # 就认为已跑完，停止执行。
            if data and len(stdout) >= len(data):
                if bytes(stdout[:len(data)]) == data and len(stdout) % len(data) == 0:
                    halted[0] = True
                    uc.emu_stop()
                    return
            if data:
                stdout.extend(data)
            uc.reg_write(UC_PPC_REG_3, x2)
            return

        if nr in (NR['exit'], NR['exit_group'], 0):
            exit_code[0] = x0 & 0xFF
            halted[0] = True
            uc.reg_write(UC_PPC_REG_3, 0)
            # 把 PC 挪到一个安全的死循环地址，让 emu_start 干净收尾
            uc.emu_stop()
            return

        if nr == NR['brk']:
            # brk(0) 返回当前断点；brk(addr) 扩展堆
            req = x0
            if req == 0 or req < brk_cur[0]:
                uc.reg_write(UC_PPC_REG_3, brk_cur[0])
                return
            need = req - brk_cur[0]
            map_page(uc, brk_cur[0], need)
            brk_cur[0] = req
            uc.reg_write(UC_PPC_REG_3, req)
            return

        if nr == NR['mmap']:
            # mmap(addr,len,prot,flags,fd,off) —— 这里只支持匿名映射
            length = x1
            fd = uc.reg_read(UC_S390X_REG_R6)
            if length == 0:
                uc.reg_write(UC_PPC_REG_3, -22)   # -EINVAL
                return
            base = brk_cur[0] + 0x10000000
            base = (base + 0xFFF) & ~0xFFF
            map_page(uc, base, length)
            brk_cur[0] = base + length
            uc.reg_write(UC_PPC_REG_3, base)
            return

        if nr == NR['getpid']:
            uc.reg_write(UC_PPC_REG_3, 4242)
            return

        if nr == NR['set_tid_address']:
            uc.reg_write(UC_PPC_REG_3, 4242)
            return

        if nr == NR['read']:
            # 没有可用输入（stdin 关闭）：返回 0 即 EOF
            uc.reg_write(UC_PPC_REG_3, 0)
            return

        if nr == NR['close']:
            uc.reg_write(UC_PPC_REG_3, 0)
            return

        if nr == NR['mprotect']:
            uc.reg_write(UC_PPC_REG_3, 0)
            return

        if nr == NR['munmap']:
            uc.reg_write(UC_PPC_REG_3, 0)
            return

        if nr == NR['open']:
            uc.reg_write(UC_PPC_REG_3, -2)     # -ENOENT
            return

        if nr == NR['ftruncate']:
            uc.reg_write(UC_PPC_REG_3, 0)
            return

        # 未实现的调用：明确报出来，而不是静默返回 0
        sys.stderr.write("[armrun] 未实现的系统调用 %d（x0=%d）\n" % (nr, x0))
        uc.reg_write(UC_PPC_REG_3, -38)        # -ENOSYS

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
        uc.mem_write(sp + 8 + i * 8, struct.pack('>Q', addr))
    uc.mem_write(sp + 8 + len(argv_list) * 8, struct.pack('>Q', 0))   # argv NULL
    uc.mem_write(sp + 8 + (len(argv_list)+1) * 8, struct.pack('>Q', 0))  # envp NULL
    uc.mem_write(sp + 8 + (len(argv_list)+2) * 8, struct.pack('>Q', 0))  # auxv AT_NULL
    uc.mem_write(sp + 8 + (len(argv_list)+3) * 8, struct.pack('>Q', 0))
    uc.reg_write(UC_PPC_REG_5, sp)

    print("开始执行（上限 %d 条指令）..." % a.steps)
    import time
    t0 = time.time()
    try:
        # PPC64 ELFv2：**r2 是 TOC 指针**，访问任何全局/常量都要经过它。
        # 正常由 crt 建立（`addis r2, r12, .TOC.-_start@ha`），我们用了
        # -nostdlib 所以没人建 —— r2=0 时会算出 0x7dd40000 这类垃圾地址，
        # 表现为程序跑飞到异常向量区。
        #
        # ELFv2 约定 r2 = TOC 基址 + 0x8000。静态链接后 .toc 已被合并，
        # 这里按 .got 地址推算（实测与代码里的 addis/addi 立即数吻合：
        # 0x30330 + 0x8000 - 0x30000 + 0x7ed0 = 0x10200 = .rodata）。
        toc = find_toc_base(a.elf)
        if toc:
            uc.reg_write(UC_PPC_REG_2, toc + 0x8000)
            print("TOC 基址    : 0x%x (r2 = 0x%x)" % (toc, toc + 0x8000))
        # ELFv2 ABI：内核把 r12 设为入口地址，crt 据此算 TOC
        uc.reg_write(UC_PPC_REG_12, entry)
        uc.emu_start(entry, 0, count=a.steps, timeout=300_000_000)
    except UcError as e:
        print("执行停止   : %s" % e)
        print("停止时 PC  : 0x%x" % uc.reg_read(UC_PPC_REG_PC))
        print("停止时 X8  : %d" % uc.reg_read(UC_PPC_REG_0))
    if not halted[0]:
        print("（未走到 exit：PC=0x%x，可能是指令上限或执行异常）"
              % uc.reg_read(UC_PPC_REG_PC))
    dt = time.time() - t0

    text = stdout.decode('utf-8', 'replace')
    print()
    print("========== ppc64 程序输出 ==========")
    print(text if text else "（空 —— 程序什么都没输出）")
    print("====================================")
    print("退出码     : %d" % exit_code[0])
    print("耗时       : %.2f 秒" % dt)
    return 0 if text else 1


if __name__ == '__main__':
    sys.exit(main())
