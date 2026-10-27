#!/usr/bin/env python3
"""
kern64run —— 在 CPU 模拟器里**真正执行**墨语言写的 ARM64 裸机内核

  python3 tools/kern64run.py /tmp/mokern64.elf [--steps N] [--keys 'help\\r']
  python3 tools/kern64run.py /tmp/mokern64.elf --disk /tmp/disk.img

与 tools/armrun.py 的差别，正是"用户态"和"裸机"的差别：

  armrun.py    模拟 **Linux 系统调用**（svc #0 处自己实现 syscall 表）
  kern64run.py 模拟 **硬件**：把内存写往 UART 数据寄存器 0x09000000 的
               字节收集成控制台输出，其余 MMIO 按读写响应

也就是说这里**内核下面什么都没有** —— 没有 Linux、没有 libc、没有
Android，只有一块 CPU 和一个串口。这正是"独立系统"的验证方式：

  机器启动后能自己打印、自己算、自己停机，就算成立。

--disk 会额外挂一块 **virtio-blk（MMIO）磁盘**，按 virtio 1.0 的
MMIO 传输层规范实现（magic 'virt' / version 2 / device id 2）。
磁盘内容落在一个真文件里，**两次启动之间保留** —— 于是"重启后文件还在"
可以被端到端验证，而不是靠驱动自己声明。

注意：模拟器只实现规范里的子集，但**寄存器布局、描述符链、avail/used
环都是真规范**，不是"驱动和模拟器约好的私有协议"。驱动拿到真 QEMU virt
上应当同样工作。
"""
import struct, sys, argparse, os

_PLIBS = os.environ.get("MO_PYLIBS", "/data/workspace/pylibs")
if os.path.isdir(_PLIBS) and _PLIBS not in sys.path:
    sys.path.insert(0, _PLIBS)

try:
    from unicorn import *
    from unicorn.arm64_const import *
except ImportError:
    sys.stderr.write("缺少 unicorn（CPU 模拟器），见 tools/pyreq.sh\n")
    sys.exit(2)

# QEMU virt 的内存布局
RAM_BASE = 0x40000000
RAM_SIZE = 16 * 1024 * 1024
UART_BASE = 0x09000000
UART_DR = UART_BASE + 0x00
UART_FR = UART_BASE + 0x18
UART_SIZE = 0x1000

# GICv2（QEMU virt 布局）：中断是**真实硬件**的一部分，不是宿主的系统调用。
# 内核通过 GICD_ISENABLER 开中断、读 GICC_IAR 取中断号、写 GICC_EOIR 应答 ——
# 这三步少一步就跑不起来，所以"应答了没有"是可以被端到端验证的。
GIC_BASE = 0x08000000
GIC_SIZE = 0x20000
GICD_CTLR = GIC_BASE + 0x000
GICD_ISENABLER0 = GIC_BASE + 0x100
GICD_ICENABLER0 = GIC_BASE + 0x180
GICC_IAR = GIC_BASE + 0x1000C
GICC_EOIR = GIC_BASE + 0x10010
TIMER_IRQ = 30                 # qemu virt 上虚拟定时器的中断号
ERET_WORD = 0xD69F03E0         # eret 的机器码

# ---- 异常模型（--exc）----
# Unicorn 不模拟异常进入/返回，所以 svc 陷入、EL0 特权检查、eret 返回都由
# 模拟器按 ARM ARM 的规范补上。用到的偏移与 EC 全是规范值，不是自定义约定：
#   同步异常（来自 lower EL，AArch64）向量偏移 = VBAR + 0x400
#   EC 0x15 = SVC from AArch64      EC 0x18 = 被陷入的 MRS/MSR/系统指令
#   EC 0x15 的 ELR 是 **下一条** 指令；EC 0x18 的 ELR 是 **陷入的那条**
#     —— 这两个方向不一样，混用会让 svc 死循环 / 特权指令被跳过。
VBAR_SYNC_LOWER = 0x400
EC_SVC64 = 0x15
EC_MSRTRAP = 0x18
SVC_INTNO = 2                  # Unicorn 里 svc 表现为 UC_HOOK_INTR，intno=2

# ---- MMU（--mmu 1）----
# 页表遍历按 ARM ARM 的**规范**：4KB granule、T0SZ=25 → 39 位 VA、从 L1 起，
# 描述符的 AP[2:1](bit7:6)、AF(bit10)、UXN(bit54) 全是规范位。于是"用户能碰
# 哪块内存"由**页表**决定，不再是模拟器的约定 —— 这正是 a64svc 留下的限制。
EC_DABT_LOWER = 0x24            # data abort from lower EL
EC_IABT_LOWER = 0x20            # instruction abort from lower EL
IFSC_TRANS = 0x4                # 取指转换错误 + level（页表描述符无效）
IFSC_PERM  = 0xC                # 取指权限错误 + level（AP 不许 / UXN=1）
# IRQ 的向量偏移：**从 lower EL(AArch64) 来的 IRQ 是 VBAR + 0x480**，不是 0x280
# —— 0x280 是"当前 EL 用 SP_EL1"那一组。只有 --tick 时才会用到。
# 早先写成 0x280，内核里那一格放的是别的入口，于是 IRQ 来了却跳进错误的代码，
# 症状是"没有任何交织"，看着像调度器没写对。这个偏移是 ARM ARM 表 D1-7 的值。
VBAR_IRQ_LOWER = 0x480
DFSC_TRANS = 0x4                # 转换错误 + level
DFSC_ACCESS = 0x8               # 访问标志错误 + level
DFSC_PERM = 0xC                 # 权限错误 + level
TTBR0_MSR_BASE = 0xD5182000
TTBR1_MSR_BASE = 0xD5182020
TCR_MSR_BASE   = 0xD5182040
MAIR_MSR_BASE  = 0xD518A200
SCTLR_MSR_BASE = 0xD5181000
# spsr_el1 在 Unicorn 里没有对应寄存器（实测：arm64_const 里不存在），
# 所以用影子值：msr spsr_el1, xN 在这里被记下，eret 时按它恢复 PSTATE。
# msr spsr_el1, xN 的底字 = 0xD5100000 | (系统寄存器编码 << 5)，spsr_el1 = 49664。
# 注意是 **按位或** 不是加：sysreg 字段横跨 bit19..5，与 opcode 的 bit20(1)
# 重叠，用加法会进位翻掉 bit20 —— 我就是这么算错过一次（得到 0xD5284000）。
# 真值由 LLVM 的汇编器独立给出：msr spsr_el1, x0 == 0xD5184000。
SPSR_MSR_BASE = 0xD5184000
# 栈指针选择寄存器：SP_EL0 = 0xC208，SP_EL1 = 0xC209（op1=0,CRn=4,CRm=1,op2=0/1）。
# 内核通常用 `msr sp_el1, xN` 指定**自己的**栈；不实现它的话，陷入后切过去的是
# 模拟器给的默认值 —— 程序照样跑完，于是"内核栈没按内核的意图设置"永远测不出来。
SP_EL0_MSR_BASE = 0xD5184100
SP_EL1_MSR_BASE = 0xD5184120
# X0..X28 在 Unicorn 枚举里连续，但 X29/X30 不是（实测：X29=1、X30=2），
# 所以不能用 X0 + Rt 直接算 —— 查表。
XREG = [UC_ARM64_REG_X0 + i if i <= 28 else
        (UC_ARM64_REG_X29 if i == 29 else UC_ARM64_REG_X30)
        for i in range(32)]

# virtio-mmio（QEMU virt 的第一块 MMIO 设备区）
VIO_BASE = 0x0A000000
VIO_SIZE = 0x1000

# PL011 标志位
RXFE = 0x10   # 接收 FIFO 空
TXFF = 0x20   # 发送 FIFO 满

# virtio-mmio 寄存器偏移
R_MAGIC, R_VERSION, R_DEVID, R_VENDOR = 0x000, 0x004, 0x008, 0x00C
R_DEVFEAT, R_DRVFEAT = 0x010, 0x020
R_QSEL, R_QNUMMAX, R_QSIZE, R_QREADY = 0x030, 0x034, 0x038, 0x044
R_QNOTIFY, R_INTSTATUS, R_STATUS = 0x050, 0x060, 0x070
R_QDESCL, R_QDESCH = 0x080, 0x084
R_QAVAILL, R_QAVAILH = 0x090, 0x094
R_QUSEDL, R_QUSEDH = 0x0A0, 0x0A4
R_CFG_CAP_LO, R_CFG_CAP_HI = 0x100, 0x104

VIRTIO_MAGIC = 0x74726976          # 'virt'
SECTOR = 512
DEFAULT_SECTORS = 2048             # 1 MiB


def load_elf(path):
    """只取 PT_LOAD 段，按物理地址铺进内存（裸机 ELF 没有虚拟内存）"""
    with open(path, "rb") as f:
        e = f.read()
    assert e[:4] == b"\x7fELF", "不是 ELF 文件"
    is64 = e[4] == 2
    assert is64, "需要 64 位 ELF"
    # ELF64 头字段偏移：e_entry@0x18  e_phoff@0x20  e_phentsize@0x36
    # e_phnum@0x38。早先按 "连续排列" 猜偏移，读出 e_phnum=0 —— 于是
    # **一个 PT_LOAD 都没加载**，程序从全 0 的内存开始执行，第一条指令
    # 就是 udf(#0)，模拟器报异常、输出为空。看着像"内核跑挂了"，
    # 其实是加载器静默失败。
    # e_machine@0x12。先前**根本没读它** —— 而 a64xselfmut 的 M4 注释却写着
    # "能抓它的是裸机层（load_elf64 断言 machine==183）"。实测 M4 未被捕获，
    # 反汇编这条链才看清：那句断言只存在于注释里。
    # 裸机加载器本就该拒绝非本架构的镜像（真硬件不会把 x86-64 代码当
    # AArch64 执行），所以这里补上，而不是只在测试脚本里比一个字节。
    (e_machine,) = struct.unpack_from("<H", e, 0x12)
    if e_machine != 183:
        raise SystemExit(
            "不是 AArch64 镜像：e_machine=%d（期望 183）。"
            "裸机加载器不会执行其它架构的代码" % e_machine)
    (e_entry,) = struct.unpack_from("<Q", e, 0x18)
    (e_phoff,) = struct.unpack_from("<Q", e, 0x20)
    (e_phentsize,) = struct.unpack_from("<H", e, 0x36)
    (e_phnum,) = struct.unpack_from("<H", e, 0x38)
    if e_phnum == 0:
        raise SystemExit("ELF 程序头数量为 0：不是可加载的裸机镜像")
    segs = []
    for i in range(e_phnum):
        off = e_phoff + i * e_phentsize
        p_type, p_flags = struct.unpack_from("<II", e, off)
        (p_offset, p_vaddr, p_paddr, p_filesz, p_memsz,
         _p_align) = struct.unpack_from("<QQQQQQ", e, off + 8)
        if p_type == 1:  # PT_LOAD
            segs.append((p_paddr, e[p_offset:p_offset + p_filesz], p_memsz))
    return e_entry, segs


class Gic:
    """极简 GICv2：只实现"开/关某号中断 + 取号 + 应答"四件事"""

    def __init__(self):
        self.ctlr = 0
        self.enable = 0
        self.in_irq = False
        self.nirq = 0
        self.tick = 0

    def irq_allowed(self):
        return bool(self.ctlr & 1) and bool((self.enable >> TIMER_IRQ) & 1) \
            and not self.in_irq


class VirtioBlk:
    """virtio 1.0 MMIO 块设备（QEMU virt 布局），backing store 是真文件"""

    def __init__(self, uc, path, sectors=DEFAULT_SECTORS):
        self.uc = uc
        self.sectors = sectors
        self.regs = {
            R_MAGIC: VIRTIO_MAGIC,
            R_VERSION: 2,
            R_DEVID: 2,          # VIRTIO_ID_BLOCK
            R_VENDOR: 0x554D4551,
            R_DEVFEAT: 0,
            R_QNUMMAX: 8,
            R_CFG_CAP_LO: sectors & 0xFFFFFFFF,
            R_CFG_CAP_HI: (sectors >> 32) & 0xFFFFFFFF,
        }
        self.desc = self.avail = self.used = 0
        self.qsize = 0
        self.ready = 0
        self.last_avail = 0
        self.busy = False
        self.pending = 0
        self.hooked = 0
        self.mc = 0
        self.io = {"read": 0, "write": 0}
        need = sectors * SECTOR
        if os.path.exists(path):
            f = open(path, "r+b")
        else:
            f = open(path, "w+b")
            f.truncate(need)
        f.truncate(need)
        self.f = f

    # ---- guest 内存访问 ----
    def g8(self, a):
        return self.uc.mem_read(a, 1)[0]

    def g16(self, a):
        return self.g8(a) | (self.g8(a + 1) << 8)

    def g32(self, a):
        return self.g16(a) | (self.g16(a + 2) << 16)

    def g64(self, a):
        return self.g32(a) | (self.g32(a + 4) << 32)

    def rd(self, a, n):
        return bytes(self.uc.mem_read(a, n))

    def wr(self, a, b):
        self.uc.mem_write(a, bytes(b))

    # ---- 寄存器读写（字节粒度：墨语言只有 load8/store8/store64）----
    def reg_read(self, off):
        if off in (R_CFG_CAP_LO, R_CFG_CAP_HI):
            base = off & ~3
            hi = self.regs.get(base + 4, 0)
            lo = self.regs.get(base, 0)
            return ((hi << 32) | lo) & 0xFFFFFFFFFFFFFFFF
        return self.regs.get(off & ~3, 0)

    def on_read(self, uc, access, addr, size, value, data):
        off = addr - VIO_BASE
        v = self.reg_read(off)
        # 在 READ 钩子里写内存会**再次触发 WRITE 钩子**：若不设闸门，读
        # 一个寄存器就等于把它当前值又写回一遍 —— 对只读寄存器无害，
        # 但读 capacity（8 字节）会被当成一次 64 位写，进而触发 process()。
        self.busy = True
        n = 8 if (off & ~3) in (R_CFG_CAP_LO, R_CFG_CAP_HI) else 4
        uc.mem_write(addr & ~3, struct.pack("<Q", v)[:n])
        self.busy = False

    def on_write(self, uc, access, addr, size, value, data):
        if self.busy:
            return
        off = addr - VIO_BASE
        reg = off & ~3
        bo = off & 3
        mask = (1 << (8 * size)) - 1
        cur = self.regs.get(reg, 0)
        newv = (cur & ~(mask << (8 * bo))) | ((value & mask) << (8 * bo))
        self.regs[reg] = newv & 0xFFFFFFFF
        if bo + size < 4:
            return                      # 32 位寄存器尚未写全
        # 只登记，不立即完成。真实设备的请求是在通知**之后**才完成的，
        # 驱动必须等 used 环；同步完成会让"不等"的驱动也照样拿到数据
        # —— 于是"必须等待"这条约束永远测不出来。
        if reg == R_QNOTIFY and self.ready:
            self.pending += 1

    # ---- 请求处理 ----
    def process(self):
        if not (self.desc and self.avail and self.used and self.qsize):
            return
        avail_idx = self.g16(self.avail + 2)
        while self.last_avail != avail_idx:
            head = self.g16(self.avail + 4 + (self.last_avail % self.qsize) * 2)
            self.last_avail = (self.last_avail + 1) & 0xFFFF
            self.run_chain(head)

    def maybe_complete(self, uc, access, addr, size, value, data):
        self.mc += 1
        if self.pending:
            self.process()
            self.pending = 0

    def run_chain(self, head):
        bufs = []
        i = head
        for _ in range(16):
            d = self.desc + i * 16
            addr = self.g64(d)
            ln = self.g32(d + 8)
            fl = self.g16(d + 12)
            nx = self.g16(d + 14)
            bufs.append((addr, ln, fl))
            if not (fl & 1):
                break
            i = nx
        if len(bufs) < 2:
            return
        req_addr, req_len, _ = bufs[0]
        rtype = self.g32(req_addr)
        sector = self.g64(req_addr + 8)
        data_addr, data_len, data_fl = bufs[1]
        st_addr, st_len, st_fl = bufs[-1]
        st = 0
        n = 0
        if rtype == 0:                                  # read
            if not (data_fl & 2):
                # 驱动没把数据缓冲标成"设备可写"，设备就一个字节都不会写。
                # 不建模这一点的话，方向位写错的驱动照样能读到数据，
                # 这条约束就永远测不出来。
                st = 1
            elif sector + 1 <= self.sectors:
                self.f.seek(sector * SECTOR)
                data = self.f.read(min(data_len, SECTOR))
                data = data + b"\0" * (min(data_len, SECTOR) - len(data))
                self.wr(data_addr, data)
                n = len(data)
                self.io["read"] += 1
            else:
                st = 1
        elif rtype == 1:                                # write
            if not (st_fl & 2):
                st = 1
            elif sector + 1 <= self.sectors:
                self.f.seek(sector * SECTOR)
                self.f.write(self.rd(data_addr, min(data_len, SECTOR)))
                self.f.flush()
                n = min(data_len, SECTOR)
                self.io["write"] += 1
            else:
                st = 1
        elif rtype == 8:                                # VIRTIO_BLK_T_GET_ID
            self.wr(data_addr, b"MO-DISK\0\0\0\0\0\0\0\0\0"[:min(data_len, 20)])
            n = min(data_len, 20)
        else:
            st = 1                                      # unsupported
        if st_fl & 2:
            self.wr(st_addr, bytes([st]))
        used_idx = self.g16(self.used + 2)
        self.wr(self.used + 4 + (used_idx % self.qsize) * 8,
                struct.pack("<II", head, n))
        self.wr(self.used + 2, struct.pack("<H", (used_idx + 1) & 0xFFFF))
        self.regs[R_INTSTATUS] = 1

    def apply_cfg(self):
        """队列地址类寄存器写完后刷新内部状态"""
        lo = lambda r: (self.regs.get(r + 4, 0) << 32) | self.regs.get(r, 0)
        self.desc = lo(R_QDESCL)
        self.avail = lo(R_QAVAILL)
        self.used = lo(R_QUSEDL)
        self.qsize = self.regs.get(R_QSIZE, 0)
        self.ready = self.regs.get(R_QREADY, 0)
        self.hooked = 1


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("elf")
    ap.add_argument("--steps", type=int, default=5_000_000)
    ap.add_argument("--keys", default="", help="注入到 UART 的输入字符")
    ap.add_argument("--disk", default="", help="virtio-blk  backing 文件（跨次保留）")
    ap.add_argument("--sectors", type=int, default=DEFAULT_SECTORS)
    ap.add_argument("--mmu", type=int, default=0,
                    help="按页表做 EL0/EL1 内存隔离（1=开）")
    ap.add_argument("--tick", type=int, default=0,
                    help="每执行 N 条指令注入一次定时器中断（0=不注入）")
    ap.add_argument("--exc", type=int, default=0,
                    help="打开异常模型：svc 陷入 / EL0 特权检查 / eret 返回")
    ap.add_argument("--initrd", default="",
                    help="第二个镜像，原样铺到物理地址（path@0xaddr）")
    args = ap.parse_args()

    entry, segs = load_elf(args.elf)

    mu = Uc(UC_ARCH_ARM64, UC_MODE_LITTLE_ENDIAN)
    mu.mem_map(RAM_BASE, RAM_SIZE)
    for paddr, data, memsz in segs:
        # 段可能跨越多个页，Unicorn 要求按页对齐映射
        start = paddr & ~0xFFF
        end = (paddr + max(memsz, len(data)) + 0xFFF) & ~0xFFF
        for a in range(start, end, 0x1000):
            try:
                mu.mem_map(a, 0x1000)
            except UcError:
                pass
        mu.mem_write(paddr, data)

    # ---- initrd：内核要加载的**另一个**镜像 ----
    # 它是"外部提供的独立可执行文件"，不是内核链接进去的一部分 ——
    # 这正是"用户空间"成立的判据：运行的东西来自内核之外。
    # 不提供时该处内存保持 0，内核必须据此报"没有镜像"，而不是碰巧跑通。
    ird = b""
    if args.initrd:
        pth, a = args.initrd.rsplit("@", 1)
        iaddr = int(a, 0)
        with open(pth, "rb") as f:
            ird = f.read()
        for x in range(iaddr & ~0xFFF, (iaddr + len(ird) + 0xFFF) & ~0xFFF, 0x1000):
            try:
                mu.mem_map(x, 0x1000)
            except UcError:
                pass
        mu.mem_write(iaddr, ird)

    mu.mem_map(UART_BASE, UART_SIZE)

    # 未注入按键时，接收 FIFO 恒为空（RXFE=1），内核读不到东西
    mu.mem_write(UART_FR, struct.pack("<I", RXFE))
    keyq = list(args.keys.encode()) if args.keys else []

    out = bytearray()
    diag = {"rd_dr": 0, "rd_fr": 0, "reads": 0, "writes": 0, "uviol": 0}

    # 按键在**读回调里**给，而且必须给在本次读之前：
    # 实测（见下）Unicorn 的 MEM_READ 钩子是在读取**之前**触发的，回调里
    # 写进 DR 的值会被这次读直接拿到。所以"先把第一个字节预置进内存"
    # 反而会让它被第一次读消耗掉之前的 hook 覆盖掉——实测注入 "help\r"
    # 只回显出 "elp"，第一个字符凭空消失。
    #
    # 早先这里还有个更基础的错：回调签名只写了 5 个参数（Unicorn 实际传
    # 6 个：uc/access/addr/size/value/data）。它从来没被执行过——之前的
    # 内核只输出不输入，读分支一次都没走到。一旦内核开始读 UART，直接
    # TypeError 崩掉。这正是"存在但从未被验证"的又一例。
    #
    # 另外：Python 绑定传给读回调的 value 恒为 0（对 MEM_READ 无意义），
    # 想知道读到什么不能看它。
    if keyq:
        mu.mem_write(UART_FR, struct.pack("<I", 0))       # 有数据
    else:
        mu.mem_write(UART_FR, struct.pack("<I", RXFE))    # FIFO 空

    def prime():
        if keyq:
            mu.mem_write(UART_DR, bytes([keyq.pop(0)]))
            mu.mem_write(UART_FR, struct.pack("<I", 0))       # 有数据
        else:
            mu.mem_write(UART_FR, struct.pack("<I", RXFE))    # FIFO 空

    def on_write(uc, access, addr, size, value, data):
        if addr == UART_DR:
            # 外设属于内核：EL0 **直接**写 UART 必须无效。真硬件靠 MMU 权限
            # 产生 data abort，这里简化为丢弃（既不进输出也不算正常）。
            # 不做这一步，"用户绕过内核直接打硬件"这条隔离性质无从验证 ——
            # 用户只要 strb 到 UART 就能说话，svc 形同虚设。
            if args.exc == 1 and cur_el(uc) == 0:
                diag["uviol"] += 1
                return
            out.append(value & 0xFF)

    def on_read(uc, access, addr, size, value, data):
        if args.exc == 1 and cur_el(uc) == 0:
            diag["uviol"] += 1
            uc.mem_write(addr & ~7, b"\xff" * 8)
            return
        if addr == UART_DR:
            diag["rd_dr"] += 1
            prime()          # 给本次读提供字节，并刷新"还有没有"
        elif addr == UART_FR:
            diag["rd_fr"] += 1

    mu.hook_add(UC_HOOK_MEM_WRITE, on_write, begin=UART_BASE,
                end=UART_BASE + UART_SIZE)
    mu.hook_add(UC_HOOK_MEM_READ, on_read, begin=UART_BASE,
                end=UART_BASE + UART_SIZE)

    # ---- virtio-blk：无论有没有 --disk 都把区域映射出来 ----
    # 关键：**没有磁盘时 magic 必须是 0**，驱动要能据此报"没找到设备"。
    # 若干脆不映射，未命中的访问会变成模拟器异常，驱动的"设备不存在"
    # 分支就永远走不到（存在但从未被验证）。
    mu.mem_map(VIO_BASE, VIO_SIZE)
    blk = None
    if args.disk:
        blk = VirtioBlk(mu, args.disk, args.sectors)

        def v_write(uc, access, addr, size, value, data):
            blk.on_write(uc, access, addr, size, value, data)
            blk.apply_cfg()

        def v_read(uc, access, addr, size, value, data):
            blk.on_read(uc, access, addr, size, value, data)

        mu.hook_add(UC_HOOK_MEM_WRITE, v_write, begin=VIO_BASE,
                    end=VIO_BASE + VIO_SIZE)
        mu.hook_add(UC_HOOK_MEM_READ, v_read, begin=VIO_BASE,
                    end=VIO_BASE + VIO_SIZE)

        # 完成时机 = 驱动第一次读 used 环。
        # 早先想在"队列地址登记时"动态挂一个只覆盖 used 环的钩子，
        # 实测 mc=0：在回调里 hook_add 不会生效。所以退一步挂整片 RAM，
        # 回调里先做地址过滤（队列没配好时直接返回）。
        def ram_read(uc, access, addr, size, value, data):
            if blk.pending and blk.used:
                if addr >= blk.used - 16:
                    if addr < blk.used + 0x400:
                        blk.maybe_complete(uc, access, addr, size, value, data)

        mu.hook_add(UC_HOOK_MEM_READ, ram_read, begin=RAM_BASE,
                    end=RAM_BASE + RAM_SIZE)

    # ---- GIC：无论有没有 --tick 都映射出来 ----
    # 不映射的话内核访问 0x08000000 会变成模拟器异常，于是"中断控制器
    # 不存在"这条分支永远走不到（存在但从未被验证）。
    mu.mem_map(GIC_BASE, GIC_SIZE)
    gic = Gic()

    def gic_write(uc, access, addr, size, value, data):
        if addr == GICD_CTLR:
            gic.ctlr = value
        elif addr == GICD_ISENABLER0:
            gic.enable |= value
        elif addr == GICD_ICENABLER0:
            gic.enable &= ~value
        elif addr == GICC_EOIR:
            gic.in_irq = False

    def gic_read(uc, access, addr, size, value, data):
        v = 0
        if addr == GICC_IAR:
            v = TIMER_IRQ if gic.in_irq else 0
        # **只能写 addr 处的这 4 个字节**。早先是写 addr & ~7 处的 8 字节：
        # GICC_IAR = 0x...000C 落在 8 字节块的**高半边**，小端下 30 被写进
        # 低半边（0x...0008），于是内核 `ldr` 读回来的是 0 —— 于是它判定
        # "不是 30 号中断" 直接返回、不写 EOIR，in_irq 永远是真，第二次 IRQ
        # 再也不来。症状是"输出毫无交织"，看着像调度器根本没轮转。
        uc.mem_write(addr, struct.pack("<I", v & 0xFFFFFFFF))

    mmu = {"on": False, "ttbr0": 0, "ttbr1": 0, "tcr": 0, "mair": 0, "sctlr": 0,
           "pending_restore": False}
    mu.hook_add(UC_HOOK_MEM_WRITE, gic_write, begin=GIC_BASE, end=GIC_BASE + GIC_SIZE)
    mu.hook_add(UC_HOOK_MEM_READ, gic_read, begin=GIC_BASE, end=GIC_BASE + GIC_SIZE)

    # ---- 异常模型 + 定时器中断 ----
    # Unicorn 不支持异常进入/返回（实测 eret 抛 UC_ERR_EXCEPTION），所以
    # svc 陷入 / EL0 特权检查 / eret 返回都由模拟器按 ARM ARM 的规范补上：
    # IRQ 入口 = VBAR + 0x280，来自 lower EL 的同步异常 = VBAR + 0x400。
    saved = {"spsr": None, "nzcv": None}
    pending = {"nzcv": None, "pst": None}
    diag["nsvc"] = 0
    diag["nmsr"] = 0
    diag["neret"] = 0
    diag["nmmu"] = 0
    diag["niabt"] = 0

    def rd64(uc, addr):
        return struct.unpack("<Q", bytes(uc.mem_read(addr, 8)))[0]

    def pt_walk(uc, va):
        """按规范遍历页表，返回 (kind, level, desc)；kind: ok / fault"""
        t0sz = mmu["tcr"] & 0x3F
        if (mmu["tcr"] >> 14) & 3 != 0:
            return ("fault", 3, 0)          # 只实现 4KB granule
        levels = (64 - t0sz - 12 + 8) // 9
        start = 4 - levels
        if start < 1:
            return ("fault", 3, 0)
        table = mmu["ttbr0"] & 0x0000FFFFFFFFF000
        for lvl in range(start, 4):
            shift = 12 + 9 * (3 - lvl)
            desc = rd64(uc, table + (((va >> shift) & 511) * 8))
            if desc & 1 == 0:
                return ("fault", lvl, 0)    # 描述符无效 = 转换错误
            if desc & 2:
                table = desc & 0x0000FFFFFFFFF000
                continue
            return ("ok", lvl, desc)
        return ("fault", 3, 0)

    def el0_perm(desc):
        """返回 (r, w, x)：AP[2:1] 决定 EL0 有没有权，AF=0 一律不许"""
        ap = (desc >> 6) & 3
        if (desc >> 10) & 1 == 0:
            return (0, 0, 0)                # 访问标志未置
        r = 1 if ap in (1, 3) else 0
        w = 1 if ap == 1 else 0
        x = 1 if (r and ((desc >> 54) & 1) == 0) else 0
        return (r, w, x)

    def mmu_apply(uc):
        """进入 EL0：把不该让用户碰的页设成 PROT_NONE（连续同权的页合并）

        必须**先把整张表走完再统一施加保护**：页表自己就躺在内核私有块里，
        边走边保护的话，走到那一页时它已经被设成 NONE，下一次 rd64 直接
        UC_ERR_NOMEM —— 症状是"用户第一条指令就取不到"，看着像页表建错，
        其实是**遍历顺序**的错。这个坑实测踩到过一次。

        遍历结果**缓存**：16MB / 4KB = 4096 页，每页 2~3 次读内存。抢占打开
        后 eret 极频繁，每次重算会让整批测试从几十秒涨到超时。缓存只在
        `msr ttbr0_el1`（换页表）时失效 —— 那正是真硬件要 tlbi 的时机。
        """
        if not mmu["on"]:
            return
        prot = mmu.get("prot")
        if prot is None:
            prot = []
            p = RAM_BASE
            while p < RAM_BASE + RAM_SIZE:
                pr = 0
                kind, lvl, desc = pt_walk(uc, p)
                if kind == "ok":
                    r, w, x = el0_perm(desc)
                    pr = (UC_PROT_READ if r else 0) | (UC_PROT_WRITE if w else 0) \
                         | (UC_PROT_EXEC if x else 0)
                prot.append(pr)
                p += 4096
            mmu["prot"] = prot
        runbase = RAM_BASE
        runprot = prot[0]
        for i in range(1, len(prot)):
            if prot[i] != runprot:
                uc.mem_protect(runbase, i * 4096 + RAM_BASE - runbase, runprot)
                runbase = RAM_BASE + i * 4096
                runprot = prot[i]
        uc.mem_protect(runbase, RAM_BASE + len(prot) * 4096 - runbase, runprot)

    def mmu_restore(uc):
        """进入 EL1：全部恢复可读写执行（内核看整张表）"""
        if mmu["on"]:
            uc.mem_protect(RAM_BASE, RAM_SIZE, UC_PROT_ALL)

    def cur_el(uc):
        # PSTATE.M[3:0]：0 = EL0t，5 = EL1h
        return uc.reg_read(UC_ARM64_REG_PSTATE) & 0xF

    def is_priv_sys(w):
        """EL0 不允许执行的系统指令：MSR/MRS/eret（hint 与 wfi 不算）

        `w >> 20` 恒为 0xD51(MSR) / 0xD53(MRS)：sysreg 字段只占 bit19..5，
        而 0xD5100000 / 0xD5300000 的 bit20 **本来就是 1**，按位或上去不会
        进位到 bit21。我一度以为 sysreg 高位会顶进 bit20 而把这里改成
        {0xD51,0xD52,0xD53,0xD54} —— 那是把"按位或"算成了"加法"，
        和上面 SPSR_MSR_BASE 注释里记过的是同一个错，又犯了一次。
        """
        t12 = w >> 20
        if t12 == 0xD51 or t12 == 0xD53:
            return True
        if t12 == 0xD50 and (w & 0xF000) == 0x4000:
            return True                 # MSR (immediate)；NOP/wfi 是 hint，不算
        return w == ERET_WORD

    def take_sync(uc, ec, retaddr):
        """从 lower EL 同步进入 EL1：ESR/ELR/切栈/切特权级，按规范"""
        # 不在**内存钩子里**直接改保护（实测会把模拟器搞崩）：置个标志，
        # 由下一条指令执行前的代码钩子统一恢复。内核第一条指令是
        # `sub sp, sp, #256`，而内核栈就在被保护的块里 —— 晚一步就来不及。
        mmu["pending_restore"] = True
        # **标志位也是上下文的一部分**。PSTATE 在 Unicorn 里读回来写回去并不
        # 覆盖 NZCV，于是抢占发生在 `cmp` 与 `b.ne` 之间时，回到用户态重新执行
        # 那条 b.ne 用的是**内核留下的**标志 —— 条件分支偶发走错。症状是
        # "栈标记明明相等却进了 stack_bad"，看寄存器值完全对不上症状。
        saved["nzcv"] = uc.reg_read(UC_ARM64_REG_NZCV)
        if cur_el(uc) == 0:
            diag["usp"] = uc.reg_read(UC_ARM64_REG_SP)
            uc.reg_write(UC_ARM64_REG_SP_EL0, uc.reg_read(UC_ARM64_REG_SP))
            uc.reg_write(UC_ARM64_REG_SP, uc.reg_read(UC_ARM64_REG_SP_EL1))
            # 记下**切完栈之后**的值：不与 SP_EL1 比对的话，"没切栈"这个缺陷
            # 完全测不出来（内核改用用户栈照样能跑完，只是踩进用户内存）。
            if "ksp" not in diag:
                diag["ksp"] = uc.reg_read(UC_ARM64_REG_SP)
        uc.reg_write(UC_ARM64_REG_ESR_EL1, ec << 26)
        uc.reg_write(UC_ARM64_REG_ELR_EL1, retaddr)
        saved["spsr"] = uc.reg_read(UC_ARM64_REG_PSTATE)
        uc.reg_write(UC_ARM64_REG_PSTATE, 0x5)          # EL1h
        uc.reg_write(UC_ARM64_REG_PC,
                     uc.reg_read(UC_ARM64_REG_VBAR_EL1) + VBAR_SYNC_LOWER)

    def take_irq(uc, retaddr):
        """定时器 IRQ：抢占式多任务的入口。

        与 take_sync 的差别只有 EC 和向量偏移，但**切栈和切特权级必须同样做全**：
        第一版只写了 PC/ELR/spsr，没动 SP 也没动 PSTATE —— 于是 IRQ 处理跑在
        **用户栈**上（而且还是 EL0 特权）。内核一保存现场就踩进用户内存，而
        用户内存是用户可以写的：抢占的上下文能被用户自己改掉。程序照样跑完，
        这类缺陷只有"切栈后记下 SP 并与 SP_EL1 比对"才测得出来。
        """
        mmu["pending_restore"] = True
        saved["nzcv"] = uc.reg_read(UC_ARM64_REG_NZCV)
        if cur_el(uc) == 0:
            uc.reg_write(UC_ARM64_REG_SP_EL0, uc.reg_read(UC_ARM64_REG_SP))
            uc.reg_write(UC_ARM64_REG_SP, uc.reg_read(UC_ARM64_REG_SP_EL1))
            if "ksp_irq" not in diag:
                diag["ksp_irq"] = uc.reg_read(UC_ARM64_REG_SP)
        saved["spsr"] = uc.reg_read(UC_ARM64_REG_PSTATE)
        # IRQ 的 preferred return address 是**被中断的那条指令**（要重跑），
        # 与 svc 的"下一条"相反。混用会让被抢占的那条指令永远丢掉一次。
        uc.reg_write(UC_ARM64_REG_ELR_EL1, retaddr)
        uc.reg_write(UC_ARM64_REG_PSTATE, 0x5)          # EL1h
        uc.reg_write(UC_ARM64_REG_PC,
                     uc.reg_read(UC_ARM64_REG_VBAR_EL1) + VBAR_IRQ_LOWER)

    def do_eret(uc):
        pst = saved["spsr"]
        if pst is None:
            pst = uc.reg_read(UC_ARM64_REG_PSTATE)
        uc.reg_write(UC_ARM64_REG_PC, uc.reg_read(UC_ARM64_REG_ELR_EL1))
        uc.reg_write(UC_ARM64_REG_PSTATE, pst)
        # **PSTATE 和 NZCV 都不能在这里写**：do_eret 只是 code hook，返回后
        # Unicorn 还要真正执行那条 eret，它会从自己内部的 SPSR 恢复 PSTATE
        #（连 NZCV 一起）—— 写进去的值当场被冲掉。实测表现为偶发的
        # "回到用户态后 EL 仍是 1" 或"标志位是内核留下的"，而指令地址、
        # 寄存器值全都对得上，症状和原因隔着一整层。
        # 所以改成"待恢复"，由 eret 之后**第一条**指令前的 code hook 落地。
        pending["pst"] = pst
        pending["nzcv"] = saved["nzcv"]
        saved["nzcv"] = None
        if (pst & 0xF) == 0:
            uc.reg_write(UC_ARM64_REG_SP, uc.reg_read(UC_ARM64_REG_SP_EL0))
            mmu_apply(uc)                   # 回到用户态：按页表收紧
        else:
            mmu_restore(uc)
        saved["spsr"] = None
        diag["neret"] += 1

    if args.tick > 0 or args.exc == 1:
        if args.tick > 0:
            gic.tick = args.tick

        def on_code(uc, addr, size, data):
            if pending["pst"] is not None:
                uc.reg_write(UC_ARM64_REG_PSTATE, pending["pst"])
                if pending["nzcv"] is not None:
                    uc.reg_write(UC_ARM64_REG_NZCV, pending["nzcv"])
                pending["pst"] = None
                pending["nzcv"] = None
            if mmu["pending_restore"]:
                mmu_restore(uc)
                mmu["pending_restore"] = False
            w = struct.unpack("<I", bytes(uc.mem_read(addr, 4)))[0]
            el = cur_el(uc)
            if args.exc == 1:
                # spsr_el1 在 Unicorn 里没有寄存器，用影子值：eret 时按它恢复
                if el != 0 and SPSR_MSR_BASE <= w <= SPSR_MSR_BASE + 31:
                    saved["spsr"] = uc.reg_read(XREG[w & 31])
                    return
                if el != 0 and SP_EL1_MSR_BASE <= w <= SP_EL1_MSR_BASE + 31:
                    uc.reg_write(UC_ARM64_REG_SP_EL1, uc.reg_read(XREG[w & 31]))
                    # 必须**跳过**这条指令：Unicorn 自己执行 `msr sp_el1` 会切
                    # 换栈选择并抛异常（intno=1），钩子 return 并不能阻止它执行。
                    uc.reg_write(UC_ARM64_REG_PC, addr + 4)
                    return
                if el != 0 and SP_EL0_MSR_BASE <= w <= SP_EL0_MSR_BASE + 31:
                    uc.reg_write(UC_ARM64_REG_SP_EL0, uc.reg_read(XREG[w & 31]))
                    uc.reg_write(UC_ARM64_REG_PC, addr + 4)
                    return
                for base, key in ((TTBR0_MSR_BASE, "ttbr0"),
                                  (TTBR1_MSR_BASE, "ttbr1"),
                                  (TCR_MSR_BASE, "tcr"),
                                  (MAIR_MSR_BASE, "mair"),
                                  (SCTLR_MSR_BASE, "sctlr")):
                    if el != 0 and base <= w <= base + 31:
                        mmu[key] = uc.reg_read(XREG[w & 31])
                        if key == "ttbr0":
                            mmu["prot"] = None
                        if key == "sctlr":
                            # 只有 --mmu 1 才生效：否则"关掉 MMU 该看到什么"
                            # 这条反向验证无从做起
                            mmu["on"] = (args.mmu == 1) and bool(mmu["sctlr"] & 1)
                        # 跳过：Unicorn 不模拟这套翻译，真执行会失配
                        uc.reg_write(UC_ARM64_REG_PC, addr + 4)
                        return
                if el == 0 and is_priv_sys(w):
                    diag["nmsr"] += 1
                    # 被陷入的系统指令：ELR 指向**陷入的那条**（与 svc 相反）
                    take_sync(uc, EC_MSRTRAP, addr)
                    return
            if w == ERET_WORD:
                do_eret(uc)
                return
            if args.tick > 0 and el == 0:
                # 只在用户态抢占：真实硬件在 EL1 也会来中断（除非 PSTATE.I=1），
                # 这里刻意只从 EL0 打断 —— 嵌套 IRQ 另是一套模型，见文档"限制"。
                gic.tick -= 1
                if gic.tick > 0:
                    return
                gic.tick = args.tick
                if not gic.irq_allowed():
                    return
                take_irq(uc, addr)
                gic.in_irq = True
                gic.nirq += 1

        # 逐指令钩子很贵，只有真的要注入中断 / 打开异常模型时才挂
        mu.hook_add(UC_HOOK_CODE, on_code)

    # 裸机内核"停机"就是 wfi 空转 —— 没有宿主可退出到，
    # 所以正常结束就是跑满步数，不算异常。
    stopped = {"reason": "步数用尽（裸机停机＝wfi 空转，属正常）"}

    def on_intr(uc, intno, data):
        if args.exc == 1 and intno == SVC_INTNO:
            diag["nsvc"] += 1
            # Unicorn 在 svc 处的 PC 已经是**下一条**指令 —— 这正是 SVC 的
            # preferred return address（ARM ARM 规定），直接拿即可。
            take_sync(uc, EC_SVC64, uc.reg_read(UC_ARM64_REG_PC))
            return
        stopped["reason"] = "停机指令 intno=%d PC=0x%x EL=%d" % (
            intno, uc.reg_read(UC_ARM64_REG_PC), cur_el(uc))
        uc.emu_stop()

    if args.mmu == 1:
        def on_prot(uc, access, addr, size, value, data):
            if not mmu["on"] or cur_el(uc) != 0:
                return True
            if not (RAM_BASE <= addr < RAM_BASE + RAM_SIZE):
                return True
            diag["nmmu"] += 1
            pc = uc.reg_read(UC_ARM64_REG_PC)
            kind, lvl, desc = pt_walk(uc, addr)
            if kind == "fault":
                dfsc = DFSC_TRANS + lvl
            elif el0_perm(desc) == (0, 0, 0):
                dfsc = DFSC_ACCESS + lvl if (desc >> 10) & 1 == 0 else DFSC_PERM + lvl
            else:
                dfsc = DFSC_PERM + lvl
            take_sync(uc, EC_DABT_LOWER, pc)
            uc.reg_write(UC_ARM64_REG_ESR_EL1,
                         (EC_DABT_LOWER << 26) | (1 << 25) | dfsc)
            uc.reg_write(UC_ARM64_REG_FAR_EL1, addr)
            return True

        mu.hook_add(UC_HOOK_MEM_READ_PROT, on_prot)
        mu.hook_add(UC_HOOK_MEM_WRITE_PROT, on_prot)

        def on_fetch(uc, access, addr, size, value, data):
            """指令中止：用户**跳进**不该执行的页。

            没有它的时候，用户 br 到内核地址会让模拟器直接报取指错误 ——
            那是"模拟器挂了"，不是"内核拦住了"。有了它，取指越界和取数越界
            一样成为内核可见的异常，系统才谈得上"自己管自己"。
            """
            if not mmu["on"] or cur_el(uc) != 0:
                return False
            diag["niabt"] += 1
            pc = uc.reg_read(UC_ARM64_REG_PC)
            kind, lvl, desc = pt_walk(uc, addr)
            if kind == "fault":
                ifsc = IFSC_TRANS + lvl          # 没映射：转换错误
            else:
                ifsc = IFSC_PERM + lvl           # 映射了但 AP 不许 / UXN=1
            take_sync(uc, EC_IABT_LOWER, pc)
            uc.reg_write(UC_ARM64_REG_ESR_EL1,
                         (EC_IABT_LOWER << 26) | (1 << 25) | ifsc)
            uc.reg_write(UC_ARM64_REG_FAR_EL1, addr)
            return True

        mu.hook_add(UC_HOOK_MEM_FETCH_PROT, on_fetch)
        mu.hook_add(UC_HOOK_MEM_FETCH_UNMAPPED, on_fetch)

    mu.hook_add(UC_HOOK_INTR, on_intr)

    sp = RAM_BASE + 12 * 1024 * 1024
    mu.reg_write(UC_ARM64_REG_SP, sp)
    # 异常模型下从 EL0 陷入时硬件会切到 SP_EL1，所以内核栈必须在这里登记，
    # 否则陷入后 sp 还是用户栈 —— 内核一保存现场就踩进用户内存。
    mu.reg_write(UC_ARM64_REG_SP_EL1, sp)
    if args.exc == 1:
        # 复位后从最高异常级开始：不显式置 EL1h 的话，_start 里的 msr/mrs
        # 会被当成 EL0 特权指令而陷入，内核根本没机会建立自己的栈。
        mu.reg_write(UC_ARM64_REG_PSTATE, 0x5)
    try:
        mu.emu_start(entry, 0, count=args.steps)
    except UcError as ex:
        stopped["reason"] = "模拟器异常: %s  PC=0x%x LR=0x%x SP=0x%x" % (
            ex, mu.reg_read(UC_ARM64_REG_PC), mu.reg_read(UC_ARM64_REG_LR),
            mu.reg_read(UC_ARM64_REG_SP))

    sys.stdout.write(out.decode("utf-8", "replace"))
    extra = ""
    if blk:
        diag["reads"] = blk.io["read"]
        diag["writes"] = blk.io["write"]
        blk.f.close()
        extra = " reads=%d writes=%d mc=%d hooked=%d used=%d" % (diag["reads"], diag["writes"], blk.mc, blk.hooked, blk.used)
    if "ksp" in diag:
        extra += " usp=0x%x ksp=0x%x uviol=%d" % (diag.get("usp", 0), diag["ksp"],
                                                  diag["uviol"])
    sys.stderr.write("\n--- kern64run: %s  rd_dr=%d rd_fr=%d irq=%d svc=%d trap=%d eret=%d%s ---\n"
                     % (stopped["reason"], diag["rd_dr"], diag["rd_fr"],
                        gic.nirq, diag["nsvc"], diag["nmsr"], diag["neret"],
                        extra))
    return 0


if __name__ == "__main__":
    sys.exit(main())
