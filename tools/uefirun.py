#!/usr/bin/env python3
"""
uefirun —— 在 CPU 模拟器里**真正执行**墨语言 UEFI 应用

  python3 tools/uefirun.py /tmp/mouefi.efi

难点：Unicorn 是纯 CPU 模拟，没有固件、没有 UEFI BootServices。
所以要在内存里**手工搭一个最小 UEFI 环境**：

  - 造一个 EFI_SYSTEM_TABLE，其 +64 处指向 ConOut
  - 造一个 ConOut，其 +8 处是 OutputString 的函数指针
  - 那个指针指向一个"魔法地址"，我们在那里下 hook：
    读 rdx（CHAR16* 字符串），转 ASCII 记录下来，
    然后伪造 EFI_SUCCESS 返回

这样就能看到 UEFI 应用**真的打印了什么**，而不只是检查 PE 头。
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

# "魔法地址"：OutputString / ClearScreen 的函数指针都指到这里，
# 我们在这些地址下 hook 来模拟固件行为。
FN_OUTSTRING = 0x7000
FN_CLEAR     = 0x7100

STACK_TOP  = 0x80000
STACK_SIZE = 0x10000
ST_ADDR    = 0x60000       # EFI_SYSTEM_TABLE
CO_ADDR    = 0x61000       # ConOut 协议对象


def build_efi_env(uc):
    """在内存里构造最小 UEFI 环境"""
    # ConOut: +8 = OutputString, +48 = ClearScreen
    uc.mem_write(CO_ADDR + 8,  struct.pack('<Q', FN_OUTSTRING))
    uc.mem_write(CO_ADDR + 48, struct.pack('<Q', FN_CLEAR))
    # EFI_SYSTEM_TABLE: +64 = ConOut
    uc.mem_write(ST_ADDR + 64, struct.pack('<Q', CO_ADDR))


def load_pe(path, uc):
    """把 PE32+ 按 SectionAlignment 铺进内存，返回入口 RVA 与 image base"""
    d = open(path, 'rb').read()
    assert d[:2] == b'MZ', "不是 PE"
    pe = struct.unpack('<I', d[0x3c:0x40])[0]
    assert d[pe:pe+4] == b'PE\0\0', "PE 签名错误"
    mach = struct.unpack('<H', d[pe+4:pe+6])[0]
    assert mach == 0x8664, "不是 x86-64（0x%x）" % mach
    nsec    = struct.unpack('<H', d[pe+6:pe+8])[0]
    optsz   = struct.unpack('<H', d[pe+20:pe+22])[0]
    opt     = pe + 24
    magic   = struct.unpack('<H', d[opt:opt+2])[0]
    assert magic == 0x20b, "不是 PE32+"
    entry   = struct.unpack('<I', d[opt+16:opt+20])[0]
    base    = struct.unpack('<Q', d[opt+24:opt+32])[0]
    sect_al = struct.unpack('<I', d[opt+32:opt+36])[0]
    file_al = struct.unpack('<I', d[opt+36:opt+40])[0]
    size_img = struct.unpack('<I', d[opt+56:opt+60])[0]

    # 映射整个 image（按页对齐）
    start = base & ~0xFFF
    end = (base + max(size_img, 0x2000) + 0xFFF) & ~0xFFF
    p = start
    while p < end:
        try:
            uc.mem_map(p, 0x1000)
        except UcError:
            pass
        p += 0x1000

    st = opt + optsz
    for i in range(nsec):
        o = st + i * 40
        name = d[o:o+8].rstrip(b'\x00').decode('latin1')
        vsize = struct.unpack('<I', d[o+8:o+12])[0]
        vaddr = struct.unpack('<I', d[o+12:o+16])[0]
        rsize = struct.unpack('<I', d[o+16:o+20])[0]
        roff  = struct.unpack('<I', d[o+20:o+24])[0]
        if vsize == 0:
            continue
        tgt = base + vaddr
        # 映射该节所在页
        s2 = tgt & ~0xFFF
        e2 = (tgt + vsize + 0xFFF) & ~0xFFF
        q = s2
        while q < e2:
            try:
                uc.mem_map(q, 0x1000)
            except UcError:
                pass
            q += 0x1000
        uc.mem_write(tgt, d[roff:roff+rsize])
    return base + entry, base


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('efi')
    ap.add_argument('--steps', type=int, default=2000000)
    a = ap.parse_args()

    uc = Uc(UC_ARCH_X86, UC_MODE_64)

    # 内存：UEFI 环境 + 魔法函数区 + 栈
    for addr, size in ((ST_ADDR, 0x2000), (FN_OUTSTRING, 0x2000),
                       (STACK_TOP - STACK_SIZE, STACK_SIZE)):
        p = addr & ~0xFFF
        e = (addr + size + 0xFFF) & ~0xFFF
        while p < e:
            try:
                uc.mem_map(p, 0x1000)
            except UcError:
                pass
            p += 0x1000

    entry, base = load_pe(a.efi, uc)
    build_efi_env(uc)
    print("image base   : 0x%x" % base)
    print("入口点       : 0x%x" % entry)

    lines = ['']

    def read_utf16(uc, addr):
        out = []
        for i in range(512):
            b = uc.mem_read(addr + i*2, 2)
            c = b[0] | (b[1] << 8)
            if c == 0:
                break
            # 保留 \r(13) / \n(10)，否则换行会被当成不可见字符变成 '.'
            if c in (10, 13) or 32 <= c < 127:
                out.append(chr(c))
            else:
                out.append('.')
        return ''.join(out)

    def hook_outstring(uc, addr, size, ud):
        # MS x64 ABI: rcx = This, rdx = CHAR16*
        s_ptr = uc.reg_read(UC_X86_REG_RDX)
        s = read_utf16(uc, s_ptr)
        # UEFI 的换行是 CRLM（\r\n），逐字符处理更稳：
        # 按 \r\n 切分在面对单独的 \r 或 \n 时会漏。
        i = 0
        while i < len(s):
            c = s[i]
            if c == '\r':
                lines.append('')
                if i + 1 < len(s) and s[i+1] == '\n':
                    i += 1
            elif c == '\n':
                lines.append('')
            else:
                lines[-1] += c
            i += 1
        # 伪造 EFI_SUCCESS 并返回到 caller
        uc.reg_write(UC_X86_REG_RAX, 0)
        ret = uc.mem_read(uc.reg_read(UC_X86_REG_RSP), 8)
        uc.reg_write(UC_X86_REG_RSP, uc.reg_read(UC_X86_REG_RSP) + 8)
        uc.reg_write(UC_X86_REG_RIP, struct.unpack('<Q', bytes(ret))[0])

    def hook_clear(uc, addr, size, ud):
        lines[:] = ['']
        uc.reg_write(UC_X86_REG_RAX, 0)
        ret = uc.mem_read(uc.reg_read(UC_X86_REG_RSP), 8)
        uc.reg_write(UC_X86_REG_RSP, uc.reg_read(UC_X86_REG_RSP) + 8)
        uc.reg_write(UC_X86_REG_RIP, struct.unpack('<Q', bytes(ret))[0])

    # 在魔法地址下 hook（begin=end=该地址，即只在这一条指令处触发）
    uc.hook_add(UC_HOOK_CODE, hook_outstring, None, FN_OUTSTRING, FN_OUTSTRING)
    uc.hook_add(UC_HOOK_CODE, hook_clear,     None, FN_CLEAR,     FN_CLEAR)

    # 栈要按 MS x64 ABI 的要求：16 字节对齐，且预留 32 字节影子空间
    sp = (STACK_TOP - 0x100) & ~0xF
    uc.reg_write(UC_X86_REG_RSP, sp)
    # EfiMain(ImageHandle, SystemTable)
    uc.reg_write(UC_X86_REG_RCX, 0x1000)
    uc.reg_write(UC_X86_REG_RDX, ST_ADDR)

    print("开始执行（上限 %d 条指令）..." % a.steps)
    try:
        uc.emu_start(entry, 0, count=a.steps, timeout=20_000_000)
    except UcError as e:
        print("执行停止     : %s" % e)

    print()
    print("========== UEFI 应用输出 ==========")
    text = '\n'.join(lines).strip()
    print(text if text else "（空 —— 应用什么都没输出）")
    print("===================================")
    return 0 if text else 1


if __name__ == '__main__':
    sys.exit(main())
