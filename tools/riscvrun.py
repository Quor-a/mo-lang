#!/usr/bin/env python3
"""
riscvrun —— 在 CPU 模拟器里**真正执行**墨语言的 RISC-V 64 原生程序

  python3 tools/riscvrun.py /tmp/andromo.rv64

与 armrun.py 同一套思路，只是架构与寄存器不同：

  ARM64:   svc #0，调用号在 x8，参数 x0-x5
  RISC-V:  ecall， 调用号在 a7，参数 a0-a5

两者都用 asm-generic 的调用号表（write=64 / exit=93 / exit_group=94 ...），
所以 syscall 的**语义处理是共用的**，只有取寄存器那几行不同。

三个架构（x86-64 原生 / ARM64 / RISC-V）都能真跑之后，
"墨语言能写系统"才不是只看产物结构。
"""
import struct, sys, argparse, os

# 依赖装在持久目录（见 tools/pyreq.sh）：沙盒会重置系统 site-packages，
# 直接 `pip install` 的包下一轮就没了。
_PLIBS = os.environ.get("MO_PYLIBS", "/data/workspace/pylibs")
if os.path.isdir(_PLIBS) and _PLIBS not in sys.path:
    sys.path.insert(0, _PLIBS)

try:
    from unicorn import *
    from unicorn.riscv_const import *
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
    ftruncate=46, brk=214, munmap=215, mmap=222, mprotect=226,
    exit=93, exit_group=94, set_tid_address=96,
    unlink=1026, unlinkat=35, io_setup=0,
)

STACK_TOP  = 0x7fffff0000
STACK_SIZE = 0x100000
BRK_BASE   = 0x40000000      # 模拟的堆起点（brk）


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
    assert mach == 243, "不是 RISC-V（machine=0x%x）" % mach
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
    a = ap.parse_args()

    uc = Uc(UC_ARCH_RISCV, UC_MODE_RISCV64)

    entry, segs = load_elf64(a.elf, uc)
    map_page(uc, STACK_TOP - STACK_SIZE, STACK_SIZE)
    print("入口点     : 0x%x" % entry)
    print("已加载段   : %s" % ", ".join("%s(%d B)" % s for s in segs))

    stdout = bytearray()
    exit_code = [0]
    halted = [False]
    brk_cur = [BRK_BASE]

    def handle(uc, intno, ud):
        nr = uc.reg_read(UC_RISCV_REG_A7)
        x0 = uc.reg_read(UC_RISCV_REG_A0)
        x1 = uc.reg_read(UC_RISCV_REG_A1)
        x2 = uc.reg_read(UC_RISCV_REG_A2)

        if nr == NR['write']:
            # write(fd, buf, count)
            data = bytes(uc.mem_read(x1, x2))
            if data:
                stdout.extend(data)
            uc.reg_write(UC_RISCV_REG_A0, x2)
            return

        if nr in (NR['exit'], NR['exit_group']):
            exit_code[0] = x0 & 0xFF
            halted[0] = True
            uc.reg_write(UC_RISCV_REG_A0, 0)
            # 把 PC 挪到一个安全的死循环地址，让 emu_start 干净收尾
            uc.emu_stop()
            return

        if nr == NR['brk']:
            # brk(0) 返回当前断点；brk(addr) 扩展堆
            req = x0
            if req == 0 or req < brk_cur[0]:
                uc.reg_write(UC_RISCV_REG_A0, brk_cur[0])
                return
            need = req - brk_cur[0]
            map_page(uc, brk_cur[0], need)
            brk_cur[0] = req
            uc.reg_write(UC_RISCV_REG_A0, req)
            return

        if nr == NR['mmap']:
            # mmap(addr,len,prot,flags,fd,off) —— 这里只支持匿名映射
            length = x1
            fd = uc.reg_read(UC_RISCV_REG_A4)
            if length == 0:
                uc.reg_write(UC_RISCV_REG_A0, -22)   # -EINVAL
                return
            base = brk_cur[0] + 0x10000000
            base = (base + 0xFFF) & ~0xFFF
            map_page(uc, base, length)
            brk_cur[0] = base + length
            uc.reg_write(UC_RISCV_REG_A0, base)
            return

        if nr == NR['getpid']:
            uc.reg_write(UC_RISCV_REG_A0, 4242)
            return

        if nr == NR['set_tid_address']:
            uc.reg_write(UC_RISCV_REG_A0, 4242)
            return

        if nr == NR['read']:
            # 没有可用输入（stdin 关闭）：返回 0 即 EOF
            uc.reg_write(UC_RISCV_REG_A0, 0)
            return

        if nr == NR['close']:
            uc.reg_write(UC_RISCV_REG_A0, 0)
            return

        if nr == NR['mprotect']:
            uc.reg_write(UC_RISCV_REG_A0, 0)
            return

        if nr == NR['munmap']:
            uc.reg_write(UC_RISCV_REG_A0, 0)
            return

        if nr == NR['openat']:
            uc.reg_write(UC_RISCV_REG_A0, -2)     # -ENOENT
            return

        if nr == NR['ftruncate']:
            uc.reg_write(UC_RISCV_REG_A0, 0)
            return

        # 未实现的调用：明确报出来，而不是静默返回 0
        sys.stderr.write("[armrun] 未实现的系统调用 %d（x0=%d）\n" % (nr, x0))
        uc.reg_write(UC_RISCV_REG_A0, -38)        # -ENOSYS

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
    uc.reg_write(UC_RISCV_REG_SP, sp)

    print("开始执行（上限 %d 条指令）..." % a.steps)
    import time
    t0 = time.time()
    try:
        uc.emu_start(entry, 0, count=a.steps, timeout=300_000_000)
    except UcError as e:
        print("执行停止   : %s" % e)
        print("停止时 PC  : 0x%x" % uc.reg_read(UC_RISCV_REG_PC))
        print("停止时 X8  : %d" % uc.reg_read(UC_RISCV_REG_A7))
    if not halted[0]:
        print("（未走到 exit：PC=0x%x，可能是指令上限或执行异常）"
              % uc.reg_read(UC_RISCV_REG_PC))
    dt = time.time() - t0

    text = stdout.decode('utf-8', 'replace')
    print()
    print("========== RISC-V 程序输出 ==========")
    print(text if text else "（空 —— 程序什么都没输出）")
    print("====================================")
    print("退出码     : %d" % exit_code[0])
    print("耗时       : %.2f 秒" % dt)
    return 0 if text else 1


if __name__ == '__main__':
    sys.exit(main())
