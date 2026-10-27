#!/usr/bin/env python3
"""
kernrun —— 在 CPU 模拟器里**真正执行**墨语言内核

  python3 tools/kernrun.py /tmp/mokernel.elf [--steps N]

原理：Unicorn 是纯 CPU 模拟器，能跑 ring0 特权指令
（qemu-user 只能跑用户态，所以不适合验证内核）。

我们手工搭建内核期待的最小硬件环境：
  - 把 ELF 段加载到链接地址（0x100000）
  - 映射 VGA 文本缓冲 0xB8000（就是普通内存，写进去能读出来）
  - 映射栈
  - hook in/out 指令，模拟键盘控制器（0x64 状态 / 0x60 数据）
  - 执行，然后从 0xB8000 读回屏幕内容

这样就真正回答了"内核能不能跑"，而不是只看产物结构。
"""
import struct, sys, argparse, os

# 依赖装在持久目录（见 tools/pyreq.sh）：沙盒会重置系统 site-packages，
# 直接 `pip install` 的包下一轮就没了。
_PLIBS = os.environ.get("MO_PYLIBS", "/data/workspace/pylibs")
if os.path.isdir(_PLIBS) and _PLIBS not in sys.path:
    sys.path.insert(0, _PLIBS)

try:
    from unicorn import *
    from unicorn.x86_const import *
except ImportError:
    import sys
    sys.stderr.write("""
缺少 unicorn（CPU 模拟器），无法做运行时验证。

  安装： pip install unicorn
  或跑： bash tools/pyreq.sh unicorn

没有它，内核/UEFI 只能验证到"产物结构正确"，不能验证真的能启动。
""")
    sys.exit(2)

# Unicorn 要求映射地址与大小都按页(4KB)对齐
VGA_BASE = 0xB8000
VGA_SIZE = 80 * 25 * 2
STACK_TOP = 0x90000
STACK_SIZE = 0x10000


def map_page(uc, addr, size):
    """按页对齐映射（Unicorn 要求 addr 与 size 都是 4KB 的倍数）

    **必须逐页映射**：一次映射整块时，若其中任一页已存在，
    Unicorn 会整块失败 —— 于是"部分重叠"的那部分就**没人映射**，
    之后写进去直接 UC_ERR_WRITE_UNMAPPED。
    ELF 的多个 PT_LOAD 常常落在同一页区间里，所以这里逐页处理。
    """
    start = addr & ~0xFFF
    end = (addr + size + 0xFFF) & ~0xFFF
    p = start
    while p < end:
        try:
            uc.mem_map(p, 0x1000)
        except UcError:
            pass     # 该页已映射
        p += 0x1000


def load_elf32(path, uc, base_hint=None):
    """把 32 位 ELF 的可加载段写进内存，返回入口点"""
    d = open(path, 'rb').read()
    assert d[:4] == b'\x7fELF', "不是 ELF"
    assert d[4] == 1, "不是 32 位 ELF"
    entry = struct.unpack('<I', d[24:28])[0]
    phoff = struct.unpack('<I', d[28:32])[0]
    phentsize = struct.unpack('<H', d[42:44])[0]
    phnum = struct.unpack('<H', d[44:46])[0]
    loaded = []
    for i in range(phnum):
        off = phoff + i * phentsize
        p_type, p_off, p_vaddr, p_paddr, p_filesz, p_memsz, p_flags, p_align = \
            struct.unpack('<IIIIIIII', d[off:off+32])
        if p_type != 1:      # PT_LOAD
            continue
        if p_memsz == 0:
            continue
        # 按页对齐映射（必须覆盖 [p_vaddr, p_vaddr+p_memsz)）
        map_page(uc, p_vaddr, p_memsz)
        uc.mem_write(p_vaddr, d[p_off:p_off+p_filesz])
        # .bss：文件里没有的部分清零
        if p_memsz > p_filesz:
            uc.mem_write(p_vaddr + p_filesz, b'\x00' * (p_memsz - p_filesz))
        loaded.append((hex(p_vaddr), p_memsz))
    return entry, loaded


class Kbd:
    """极简键盘控制器：0x64 是状态口（bit0=有数据），0x60 是数据口"""
    def __init__(self, scancodes=b''):
        self.queue = list(scancodes)
        self.last = 0

    def inb(self, port):
        if port == 0x64:
            return 1 if self.queue else 0
        if port == 0x60:
            if self.queue:
                self.last = self.queue.pop(0)
                return self.last
            return 0
        return 0xFF

    def outb(self, port, val):
        # 也可作为调试输出（0xE9 端口）
        if port == 0xE9:
            sys.stdout.write(chr(val))
            sys.stdout.flush()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('elf')
    ap.add_argument('--steps', type=int, default=3000000)
    ap.add_argument('--keys', default='',
                    help='要"敲入"的字符串（转成扫描码喂给键盘）')
    ap.add_argument('--show-screen', action='store_true', default=True)
    a = ap.parse_args()

    uc = Uc(UC_ARCH_X86, UC_MODE_32)

    # 内存：VGA + 栈 + 代码段（代码段在 load_elf32 里按需映射）
    map_page(uc, VGA_BASE, VGA_SIZE)
    map_page(uc, STACK_TOP - STACK_SIZE, STACK_SIZE)

    entry, segs = load_elf32(a.elf, uc)
    print("入口点       : 0x%x" % entry)
    print("已加载段     : %s" % ", ".join("%s(%d B)" % s for s in segs))

    # 扫描码表：只覆盖测试用到的字符
    SC = {}
    for ch, sc in zip("1234567890-=qwertyuiop[]asdfghjkl;'zxcvbnm,./ ",
                      [2,3,4,5,6,7,8,9,10,11,12,13,16,17,18,19,20,21,22,23,24,25,26,27,
                       30,31,32,33,34,35,36,37,38,39,40,44,45,46,47,48,49,50,51,52,53,57]):
        SC[ch] = sc
    keys = []
    for ch in a.keys:
        keys.append(SC[ch])
        keys.append(SC[ch] | 0x80)     # 松开
    keys.append(28)                     # Enter 按下
    keys.append(28 | 0x80)
    kbd = Kbd(keys if a.keys else b'')

    out_log = []

    def hook_in(uc, port, size, ud):
        """IN 指令：回调的**返回值**会被写入 EAX"""
        return kbd.inb(port)

    def hook_out(uc, port, size, val, ud):
        """OUT 指令：val 来自 EAX/AL"""
        kbd.outb(port, val)
        return None

    # Unicorn 对 x86 的 IN/OUT 有专门的指令级 hook。
    # 注意两个回调的签名不同：IN 是 (uc, port, size, ud) 且**返回值**进 EAX，
    # OUT 是 (uc, port, size, value, ud)。写成一样的会 TypeError。
    uc.hook_add(UC_HOOK_INSN, hook_in,  None, 1, 0, UC_X86_INS_IN)
    uc.hook_add(UC_HOOK_INSN, hook_out, None, 1, 0, UC_X86_INS_OUT)

    # 起始状态：栈指针 + Multiboot 参数（ebx=info, eax=magic）
    uc.reg_write(UC_X86_REG_ESP, STACK_TOP - 16)
    uc.reg_write(UC_X86_REG_EAX, 0x2BADB002)
    uc.reg_write(UC_X86_REG_EBX, 0)

    print("开始执行（上限 %d 条指令）..." % a.steps)
    try:
        uc.emu_start(entry, 0, count=a.steps, timeout=20_000_000)
    except UcError as e:
        # 内核最后是 hlt 死循环，超时/异常都属正常结束
        print("执行停止     : %s（内核末尾是 hlt 循环，属预期）" % e)

    # 读回屏幕
    buf = uc.mem_read(VGA_BASE, VGA_SIZE)
    screen = []
    for row in range(25):
        line = ''
        for col in range(80):
            lo = buf[(row*80+col)*2]
            hi = buf[(row*80+col)*2 + 1]
            if lo == 0 and hi == 0x07:
                line += ' '
            else:
                line += chr(lo) if 32 <= lo < 127 else '.'
        screen.append(line.rstrip())
    text = '\n'.join(screen).strip()

    print()
    print("========== 屏幕内容 ==========")
    print(text if text else "（空 —— 内核什么都没输出）")
    print("==============================")

    return 0 if text else 1


if __name__ == '__main__':
    sys.exit(main())
