# a64pkg —— 自举 aarch64 的 **包管理与执行环境**
#
# 与 a64exec 的差别：那一版 initrd 里放的是赤裸的 ELF，这一版放的是**包**
# —— 一串可打印字节：`MOPK1|<name>|<ver>|<len>|<hex>|<sum>`。内核把它解开、
# 算出校验和、对不上就拒绝执行，对上了才把 payload（用户 ELF）加载运行。
#
# 于是"自带运行和执行环境"第一次有了可验证的含义：
#   包是从外面送进来的数据，不是内核的一部分；装不装得进去由校验和说了算。
#
# 用户程序运行时还能用内核的文件系统（svc 200..204）。文件的**内容**放在
# 内核私有块，用户只能通过 svc 读写，直接读会被页表拦下 —— 这正是"文件由
# 内核保管"与"用户自己有块内存"的区别。
#
# 布局（每块 2MB）：
#   0x40000000  block0  AP=00  内核代码/数据
#   0x40200000  block1  AP=01  用户区：用户程序的 text/data/bss/栈
#   0x40400000  block2  AP=00  内核私有：栈、页表、secret、initrd、payload、FS
#   0x40600000  block3  未映射 —— EL0 访问是转换错误
#   payload 解包到 0x40420000，文件槽在 0x40430000（8 × 256 字节）
#
# 期望输出（见 tools/a64pkgtest.sh）：
#   MO-PKG / PK n=<len> / U1 / 5050 / 0 / 8 / 8 / 5050 / 1 / PF2 / D / EXIT 7 / V OK

        .text
        .globl _start
_start:
        mov     x0, #0
        movk    x0, #0x4040, lsl #16
        add     x0, x0, #2048
        add     x0, x0, #2048           # 0x40401000 内核栈
        msr     sp_el1, x0
        ldaddr  x0, vectors
        msr     vbar_el1, x0
        mov     x0, #0
        movk    x0, #0x4040, lsl #16    # 0x40400000 用户区末端
        sub     x0, x0, #16
        msr     sp_el0, x0
        ldaddr  x20, msg_boot
        bl      puts
        # secret 放在内核私有块：退出时用它验"用户碰没碰到内核"
        mov     x9, #0
        movk    x9, #0x4040, lsl #16
        add     x9, x9, #2048           # 0x40400800
        mov     x10, #0xBEEF
        str     x10, [x9]
        bl      build_pt
        bl      enable_mmu

        # 污染用户区：不清零的话"加载器有没有按 p_memsz 清零 bss"测不出来
        bl      poison

        # ── 解包 ──
        bl      unpack
        mov     x24, x0
        cmp     x24, #0
        b.lt    pkg_fail
        ldaddr  x20, msg_pk
        bl      puts
        mov     x0, x24
        bl      printdec

        # ── 加载 payload 里的用户 ELF ──
        mov     x0, #0
        movk    x0, #0x4042, lsl #16    # 0x40420000 = payload
        bl      load_elf
        cmp     x0, #0
        b.lt    load_fail
        msr     elr_el1, x0
        mov     x1, #0                  # PSTATE = 0 → EL0t
        msr     spsr_el1, x1
        eret

pkg_fail:
        ldaddr  x20, msg_bad
        bl      puts
        mov     x0, x24
        neg     x0, x0
        bl      printdec
        b       halt

load_fail:
        mov     x9, x0
        ldaddr  x20, msg_err
        bl      puts
        mov     x0, x9
        neg     x0, x0
        bl      printdec
        b       halt

# ── 建页表 ──
build_pt:
        mov     x11, #0
        movk    x11, #0x4040, lsl #16
        add     x11, x11, #2048
        add     x11, x11, #2048
        add     x11, x11, #2048         # 0x40403000 L2_dev
        mov     x14, #0
        movk    x14, #0x4040, lsl #16
        add     x14, x14, #2048
        add     x14, x14, #2048
        add     x14, x14, #2048
        add     x14, x14, #2048         # 0x40404000 L2_ram
        mov     x13, #0
        movk    x13, #0x4040, lsl #16
        add     x13, x13, #2048
        add     x13, x13, #2048         # 0x40402000 L1
        add     x9, x11, #3
        str     x9, [x13, #0]
        add     x9, x14, #3
        str     x9, [x13, #8]

        # L2_dev[72] → UART：设备内存，EL1 独享
        mov     x9, #0x0405
        movk    x9, #0, lsl #16
        movk    x9, #0x0900, lsl #32
        movk    x9, #0x0060, lsl #48
        str     x9, [x11, #576]

        # L2_ram[0] → 0x40000000 内核代码/数据。
        # 这里**不能**设成 AP=00：模拟器是页级保护，不区分 EL，内核块一旦在
        # EL0 视图里没有 X，svc 陷入后内核自己也取不到指。
        mov     x9, #0x0441
        movk    x9, #0, lsl #16
        movk    x9, #0x4000, lsl #32
        movk    x9, #0x0020, lsl #48
        str     x9, [x14, #0]
        # L2_ram[1] → 0x40200000 用户区：AP=01（EL0 可读写）、UXN=0
        mov     x9, #0x0441
        movk    x9, #0, lsl #16
        movk    x9, #0x4020, lsl #32
        movk    x9, #0x0020, lsl #48
        str     x9, [x14, #8]
        # L2_ram[2] → 0x40400000 内核私有（含 initrd/payload/FS）：AP=00
        mov     x9, #0x0401
        movk    x9, #0, lsl #16
        movk    x9, #0x4040, lsl #32
        movk    x9, #0x0040, lsl #48
        str     x9, [x14, #16]
        ret

enable_mmu:
        mov     x9, #0
        movk    x9, #0x4040, lsl #16
        add     x9, x9, #2048
        add     x9, x9, #2048           # L1
        msr     ttbr0_el1, x9
        mov     x9, #0x3519
        msr     tcr_el1, x9
        mov     x9, #255
        msr     mair_el1, x9
        dsb
        isb
        mov     x9, #0x1005
        msr     sctlr_el1, x9
        isb
        ret

# ── 污染用户区 ──
poison:
        mov     x9, #0
        movk    x9, #0x4020, lsl #16
        mov     x10, #0
        movk    x10, #0x4021, lsl #16
        mov     x11, #0xA5A5
        movk    x11, #0xA5A5, lsl #16
        movk    x11, #0xA5A5, lsl #32
        movk    x11, #0xA5A5, lsl #48
ps_loop:
        cmp     x9, x10
        b.ge    ps_ret
        str     x11, [x9]
        add     x9, x9, #8
        b       ps_loop
ps_ret:
        ret

# ── unpack：解 initrd 里的包，返回 x0 = payload 长度，或负错误码 ──
#   -1 magic   -2 段数≠6   -3 hex 长度与 len 不符   -4 非法 hex
#   -5 校验和不符   -6 payload 超出容量（上限 1024）
# 六个失败必须是**六个不同的码**：统一返回 -1 的话，调用方分不清
# "包被截断"和"包被改过"，而这两件事该做的反应完全不同（重传 vs 拒收）。
unpack:
        sub     sp, sp, #64
        str     x30, [sp, #0]
        mov     x9, #0
        movk    x9, #0x4041, lsl #16    # 0x40410000 = initrd
        ldrb    w1, [x9, #0]
        mov     x2, #77                 # 'M'
        cmp     x1, x2
        b.ne    up_magic
        ldrb    w1, [x9, #1]
        mov     x2, #79                 # 'O'
        cmp     x1, x2
        b.ne    up_magic
        ldrb    w1, [x9, #2]
        mov     x2, #80                 # 'P'
        cmp     x1, x2
        b.ne    up_magic
        ldrb    w1, [x9, #3]
        mov     x2, #75                 # 'K'
        cmp     x1, x2
        b.ne    up_magic
        ldrb    w1, [x9, #4]
        mov     x2, #49                 # '1'
        cmp     x1, x2
        b.ne    up_magic
        # 按 '|' 分段，记下每段 [start, end)
        mov     x10, x9                 # 当前段起始
        mov     x15, x9                 # 扫描指针
        mov     x14, #0                 # 已完成段数
up_scan:
        ldrb    w16, [x15]
        cmp     x16, #0
        b.eq    up_last
        mov     x17, #10                # '\n'
        cmp     x16, x17
        b.eq    up_last
        mov     x17, #124               # '|'
        cmp     x16, x17
        b.ne    up_next
        bl      up_rec
        add     x15, x15, #1
        mov     x10, x15
        b       up_scan
up_next:
        add     x15, x15, #1
        b       up_scan
up_last:
        bl      up_rec
        mov     x18, #6
        cmp     x14, x18
        b.ne    up_nseg
        # len = atoi(段 3)
        ldaddr  x13, segs
        ldr     x5, [x13, #48]
        ldr     x6, [x13, #56]
        bl      atoi
        mov     x19, x0
        mov     x18, #1024
        cmp     x19, x18
        b.gt    up_big
        # hex 段长度必须 == 2*len（少一个字符就只能解出半个包）
        ldaddr  x13, segs
        ldr     x5, [x13, #64]
        ldr     x6, [x13, #72]
        mov     x18, x6
        sub     x18, x18, x5
        mov     x20, #2
        mul     x21, x19, x20
        cmp     x18, x21
        b.ne    up_hlen
        bl      hexdec
        cmp     x0, #0
        b.lt    up_hex                  # hexdec 返回 -1：非法字符
        cmp     x0, x19
        b.ne    up_hlen
        # sum：与算出来的 FNV-1a 比
        ldaddr  x13, segs
        ldr     x5, [x13, #80]
        ldr     x6, [x13, #88]
        bl      atoi
        mov     x22, x0
        bl      fnv
        cmp     x0, x22
        b.ne    up_sum
        mov     x0, x19
        b       up_ok

up_magic:
        mov     x0, #1
        b       up_neg
up_nseg:
        mov     x0, #2
        b       up_neg
up_hlen:
        mov     x0, #3
        b       up_neg
up_hex:
        mov     x0, #4
        b       up_neg
up_big:
        mov     x0, #6
        b       up_neg
up_sum:
        mov     x0, #5
        b       up_neg
up_neg:
        neg     x0, x0
up_ok:
        ldr     x30, [sp, #0]
        add     sp, sp, #64
        ret

# 记录一段 [x10, x15)
up_rec:
        ldaddr  x23, segs
        mov     x24, #16
        mul     x24, x14, x24
        add     x23, x23, x24
        str     x10, [x23, #0]
        str     x15, [x23, #8]
        add     x14, x14, #1
        ret

# atoi：x5 = 起、x6 = 止 → x0 = 值
atoi:
        mov     x2, #0
at_loop:
        cmp     x5, x6
        b.ge    at_ret
        ldrb    w3, [x5]
        sub     x3, x3, #48
        cmp     x3, #0
        b.lt    at_ret
        cmp     x3, #9
        b.gt    at_ret
        mov     x4, #10
        mul     x2, x2, x4
        add     x2, x2, x3
        add     x5, x5, #1
        b       at_loop
at_ret:
        mov     x0, x2
        ret

# hexdec：x5 = hex 起、x6 = hex 止 → x0 = 解出的字节数（失败 -1）
hexdec:
        sub     sp, sp, #32
        str     x30, [sp, #0]
        mov     x7, #0
        movk    x7, #0x4042, lsl #16    # 0x40420000 = payload
        mov     x8, #0
hd_loop:
        cmp     x5, x6
        b.ge    hd_ret
        ldrb    w2, [x5]
        mov     x0, x2
        bl      hexval
        cmp     x0, #0
        b.lt    hd_bad
        lsl     x2, x0, #4
        add     x5, x5, #1
        ldrb    w3, [x5]
        mov     x0, x3
        bl      hexval
        cmp     x0, #0
        b.lt    hd_bad
        orr     x2, x2, x0
        strb    w2, [x7]
        add     x7, x7, #1
        add     x5, x5, #1
        add     x8, x8, #1
        b       hd_loop
hd_ret:
        mov     x0, x8
        ldr     x30, [sp, #0]
        add     sp, sp, #32
        ret
hd_bad:
        mov     x0, #1
        neg     x0, x0
        ldr     x30, [sp, #0]
        add     sp, sp, #32
        ret

# hexval：x0 = 字符 → x0 = 值，非法返回 -1
hexval:
        cmp     x0, #48
        b.lt    hv_bad
        cmp     x0, #58
        b.lt    hv_dig
        cmp     x0, #65
        b.lt    hv_bad
        cmp     x0, #71
        b.lt    hv_up
        cmp     x0, #97
        b.lt    hv_bad
        cmp     x0, #103
        b.lt    hv_lo
        b       hv_bad
hv_dig:
        sub     x0, x0, #48
        ret
hv_up:
        sub     x0, x0, #55
        ret
hv_lo:
        sub     x0, x0, #87
        ret
hv_bad:
        mov     x0, #1
        neg     x0, x0
        ret

# fnv：对 payload 前 x19 字节算 FNV-1a(32)，返回 x0
fnv:
        mov     x7, #0
        movk    x7, #0x4042, lsl #16
        mov     x2, #0x9DC5
        movk    x2, #0x811C, lsl #16    # FNV offset basis
        mov     x3, #0x0193
        movk    x3, #0x0100, lsl #16    # FNV prime
        mov     x4, #0xFFFF
        movk    x4, #0xFFFF, lsl #16
        mov     x8, #0
fn_loop:
        cmp     x8, x19
        b.ge    fn_ret
        ldrb    w9, [x7]
        eor     x2, x2, x9
        mul     x2, x2, x3
        and     x2, x2, x4
        add     x7, x7, #1
        add     x8, x8, #1
        b       fn_loop
fn_ret:
        mov     x0, x2
        ret

# ── load_elf：x0 = 镜像基址，返回 x0 = entry（成功）或负错误码 ──
#   -1 magic   -2 非 ET_EXEC  -3 机器不是 aarch64  -4 phentsize≠56
#   -5 phnum 越界  -6 entry 不在用户区  -7 段越界  -8 没有 PT_LOAD
load_elf:
        mov     x26, x0
        ldrb    w1, [x26, #0]
        mov     x2, #127
        cmp     x1, x2
        b.ne    le_magic
        ldrb    w1, [x26, #1]
        mov     x2, #69
        cmp     x1, x2
        b.ne    le_magic
        ldrb    w1, [x26, #2]
        mov     x2, #76
        cmp     x1, x2
        b.ne    le_magic
        ldrb    w1, [x26, #3]
        mov     x2, #70
        cmp     x1, x2
        b.ne    le_magic
        ldr     x1, [x26, #16]
        lsl     x2, x1, #48
        lsr     x2, x2, #48             # e_type
        mov     x3, #2
        cmp     x2, x3
        b.ne    le_type
        lsr     x2, x1, #16
        lsl     x2, x2, #48
        lsr     x2, x2, #48             # e_machine
        mov     x3, #183
        cmp     x2, x3
        b.ne    le_mach
        ldr     x1, [x26, #48]
        lsr     x2, x1, #48             # e_phentsize
        mov     x3, #56
        cmp     x2, x3
        b.ne    le_phes
        ldr     x1, [x26, #56]
        lsl     x2, x1, #48
        lsr     x2, x2, #48             # e_phnum
        mov     x3, #0
        cmp     x2, x3
        b.le    le_phn
        mov     x3, #4
        cmp     x2, x3
        b.gt    le_phn
        mov     x1, x2
        ldr     x27, [x26, #24]         # e_entry
        mov     x4, #0
        movk    x4, #0x4020, lsl #16
        cmp     x27, x4
        b.lt    le_entry
        mov     x4, #0
        movk    x4, #0x4040, lsl #16
        cmp     x27, x4
        b.ge    le_entry
        ldr     x5, [x26, #32]          # e_phoff
        add     x5, x5, x26
        mov     x6, #0                  # i
        mov     x7, #0                  # 已加载段数
le_loop:
        cmp     x6, x1
        b.ge    le_done
        mov     x8, #56
        mul     x9, x6, x8
        add     x10, x5, x9
        ldr     w11, [x10, #0]          # p_type
        cmp     x11, #1
        b.ne    le_next
        ldr     x12, [x10, #8]          # p_offset
        ldr     x13, [x10, #16]         # p_vaddr
        ldr     x14, [x10, #32]         # p_filesz
        ldr     x15, [x10, #40]         # p_memsz
        mov     x16, #0
        movk    x16, #0x4020, lsl #16
        cmp     x13, x16
        b.lt    le_seg
        add     x17, x13, x15
        mov     x16, #0
        movk    x16, #0x4040, lsl #16
        cmp     x17, x16
        b.gt    le_seg
        # 复制用**指针递增**而不是 [base, idx]：本汇编器对 ldrb/strb 的
        # 寄存器偏移编码与 ldr 的 scale 不同，写成 [x18, x20] 会静默退化成
        # [x18] —— 于是整段只填了第一个字节。
        add     x18, x26, x12           # src = img + p_offset
        mov     x22, x18
        mov     x23, x13                # dst = p_vaddr
        mov     x20, #0
le_copy:
        cmp     x20, x14
        b.ge    le_zero
        ldrb    w21, [x22]
        strb    w21, [x23]
        add     x22, x22, #1
        add     x23, x23, #1
        add     x20, x20, #1
        b       le_copy
le_zero:
        cmp     x20, x15
        b.ge    le_next2
        mov     x21, #0
        strb    w21, [x23]
        add     x23, x23, #1
        add     x20, x20, #1
        b       le_zero
le_next2:
        add     x7, x7, #1
le_next:
        add     x6, x6, #1
        b       le_loop
le_done:
        cmp     x7, #0
        b.eq    le_noload
        mov     x0, x27
        ret
le_magic:
        mov     x0, #1
        neg     x0, x0
        ret
le_type:
        mov     x0, #2
        neg     x0, x0
        ret
le_mach:
        mov     x0, #3
        neg     x0, x0
        ret
le_phes:
        mov     x0, #4
        neg     x0, x0
        ret
le_phn:
        mov     x0, #5
        neg     x0, x0
        ret
le_entry:
        mov     x0, #6
        neg     x0, x0
        ret
le_seg:
        mov     x0, #7
        neg     x0, x0
        ret
le_noload:
        mov     x0, #8
        neg     x0, x0
        ret

# ── 异常向量表 ──
        .align  2048
vectors:
        .zero   1024
sync_lower:
        b       exc_entry

exc_entry:
        sub     sp, sp, #256
        stp     x0, x1, [sp, #0]
        stp     x2, x3, [sp, #16]
        stp     x4, x5, [sp, #32]
        stp     x6, x7, [sp, #48]
        stp     x8, x9, [sp, #64]
        stp     x10, x11, [sp, #80]
        stp     x12, x13, [sp, #96]
        stp     x14, x15, [sp, #112]
        stp     x16, x17, [sp, #128]
        stp     x18, x19, [sp, #144]
        stp     x20, x21, [sp, #160]
        stp     x22, x23, [sp, #176]
        stp     x24, x25, [sp, #192]
        stp     x26, x27, [sp, #208]
        stp     x28, x29, [sp, #224]
        str     x30, [sp, #240]
        mrs     x0, esr_el1
        lsr     x1, x0, #26
        mov     x2, #21
        cmp     x1, x2
        b.eq    do_svc
        mov     x2, #36
        cmp     x1, x2
        b.eq    do_dabt
        ldaddr  x20, msg_unknown
        bl      puts
        b       halt

do_dabt:
        ldaddr  x9, faultn
        ldr     x10, [x9]
        add     x10, x10, #1
        str     x10, [x9]
        mrs     x0, esr_el1
        lsl     x10, x0, #58
        lsr     x10, x10, #58
        mrs     x11, far_el1
        mov     x12, #12
        cmp     x10, x12
        b.ge    dabt_perm
        ldaddr  x20, msg_trf
        bl      puts
        b       dabt_blk
dabt_perm:
        ldaddr  x20, msg_pf
        bl      puts
dabt_blk:
        lsr     x10, x11, #21
        lsl     x10, x10, #61
        lsr     x10, x10, #61
        add     x10, x10, #48
        mov     x25, #0
        movk    x25, #0x0900, lsl #16
        strb    w10, [x25]
        mov     x10, #10
        strb    w10, [x25]
        mrs     x0, elr_el1
        add     x0, x0, #4
        msr     elr_el1, x0
        b       exc_ret

do_svc:
        ldr     x8, [sp, #64]
        mov     x9, #64
        cmp     x8, x9
        b.eq    sys_write
        mov     x9, #65
        cmp     x8, x9
        b.eq    sys_putdec
        mov     x9, #93
        cmp     x8, x9
        b.eq    sys_exit
        mov     x9, #200
        cmp     x8, x9
        b.eq    sys_fs_create
        mov     x9, #201
        cmp     x8, x9
        b.eq    sys_fs_write
        mov     x9, #202
        cmp     x8, x9
        b.eq    sys_fs_read
        mov     x9, #203
        cmp     x8, x9
        b.eq    sys_fs_size
        mov     x9, #204
        cmp     x8, x9
        b.eq    sys_fs_count
        mov     x0, #38
        neg     x0, x0
        str     x0, [sp, #0]
        b       exc_ret

# write：buf 必须落在**用户区** [0x40200000, 0x40400000)
sys_write:
        ldr     x1, [sp, #8]
        ldr     x2, [sp, #16]
        mov     x9, #0
        movk    x9, #0x4020, lsl #16
        cmp     x1, x9
        b.lt    sw_bad
        mov     x9, #0
        movk    x9, #0x4040, lsl #16
        cmp     x1, x9
        b.ge    sw_bad
        mov     x25, #0
        movk    x25, #0x0900, lsl #16
        mov     x11, x1
        mov     x12, x2
sw_loop:
        cmp     x12, #0
        b.eq    sw_done
        ldrb    w13, [x11]
        strb    w13, [x25]
        add     x11, x11, #1
        sub     x12, x12, #1
        b       sw_loop
sw_done:
        mov     x0, #0
        str     x0, [sp, #0]
        b       exc_ret
sw_bad:
        mov     x0, #14
        neg     x0, x0
        str     x0, [sp, #0]
        b       exc_ret

sys_putdec:
        ldr     x0, [sp, #8]
        bl      printdec
        mov     x0, #0
        str     x0, [sp, #0]
        b       exc_ret

# ── 文件系统 ──
#   fs_names[id] = 名字（≤7 字节）、fs_len[id] = 长度
#   内容在内核私有块 0x40430000 + id*256，用户只能通过 svc 碰
#   8 个槽、每槽 256 字节
sys_fs_create:                          # x0 = 名字指针，x1 = 长度
        ldr     x1, [sp, #0]
        ldr     x2, [sp, #8]
        mov     x9, #0
        movk    x9, #0x4020, lsl #16
        cmp     x1, x9
        b.lt    fc_bad
        mov     x9, #0
        movk    x9, #0x4040, lsl #16
        cmp     x1, x9
        b.ge    fc_bad
        mov     x9, #7
        cmp     x2, x9
        b.gt    fc_nm
        ldaddr  x9, fs_count
        ldr     x10, [x9]
        mov     x11, #8
        cmp     x10, x11
        b.ge    fc_full
        mov     x12, x10                 # id
        # 先清名字槽，再逐字节写
        ldaddr  x13, fs_names
        mov     x14, #8
        mul     x14, x12, x14
        add     x13, x13, x14
        mov     x15, #0
        str     x15, [x13]
        mov     x16, x1
        mov     x17, #0
fc_nmloop:
        cmp     x17, x2
        b.ge    fc_nmdone
        ldrb    w18, [x16]
        strb    w18, [x13]
        add     x16, x16, #1
        add     x13, x13, #1
        add     x17, x17, #1
        b       fc_nmloop
fc_nmdone:
        ldaddr  x13, fs_len
        mov     x14, #8
        mul     x14, x12, x14
        add     x13, x13, x14
        mov     x15, #0
        str     x15, [x13]
        add     x10, x10, #1
        ldaddr  x9, fs_count
        str     x10, [x9]
        str     x12, [sp, #0]
        b       exc_ret
fc_nm:
        mov     x0, #1
        neg     x0, x0
        str     x0, [sp, #0]
        b       exc_ret
fc_full:
        mov     x0, #2
        neg     x0, x0
        str     x0, [sp, #0]
        b       exc_ret
fc_bad:
        mov     x0, #14
        neg     x0, x0
        str     x0, [sp, #0]
        b       exc_ret

# 算出文件槽的地址：x0 = id → x0 = 地址（越界返回 0）
fs_slot:
        mov     x9, #0
        movk    x9, #0x4043, lsl #16    # 0x40430000
        mov     x10, #256
        mul     x10, x0, x10
        add     x0, x9, x10
        ret

sys_fs_write:                           # x0 = id, x1 = buf, x2 = n
        ldr     x1, [sp, #0]
        ldr     x2, [sp, #8]
        ldr     x3, [sp, #16]
        ldaddr  x9, fs_count
        ldr     x10, [x9]
        cmp     x1, x10
        b.ge    fw_bad
        mov     x9, #0
        movk    x9, #0x4020, lsl #16
        cmp     x2, x9
        b.lt    fw_bad
        mov     x9, #0
        movk    x9, #0x4040, lsl #16
        cmp     x2, x9
        b.ge    fw_bad
        mov     x9, #256
        cmp     x3, x9
        b.gt    fw_big
        mov     x0, x1
        bl      fs_slot
        mov     x11, x0                  # dst
        mov     x12, x2                  # src
        mov     x13, x3                  # n
        mov     x14, #0
fw_loop:
        cmp     x14, x13
        b.ge    fw_done
        ldrb    w15, [x12]
        strb    w15, [x11]
        add     x12, x12, #1
        add     x11, x11, #1
        add     x14, x14, #1
        b       fw_loop
fw_done:
        ldaddr  x9, fs_len
        mov     x10, #8
        mul     x10, x1, x10
        add     x9, x9, x10
        str     x13, [x9]
        str     x13, [sp, #0]
        b       exc_ret
fw_big:
        mov     x0, #2
        neg     x0, x0
        str     x0, [sp, #0]
        b       exc_ret
fw_bad:
        mov     x0, #1
        neg     x0, x0
        str     x0, [sp, #0]
        b       exc_ret

sys_fs_read:                            # x0 = id, x1 = buf, x2 = n
        ldr     x1, [sp, #0]
        ldr     x2, [sp, #8]
        ldr     x3, [sp, #16]
        ldaddr  x9, fs_count
        ldr     x10, [x9]
        cmp     x1, x10
        b.ge    fr_bad
        mov     x9, #0
        movk    x9, #0x4020, lsl #16
        cmp     x2, x9
        b.lt    fr_bad
        mov     x9, #0
        movk    x9, #0x4040, lsl #16
        cmp     x2, x9
        b.ge    fr_bad
        # n = min(n, fs_len[id])
        ldaddr  x9, fs_len
        mov     x10, #8
        mul     x10, x1, x10
        add     x9, x9, x10
        ldr     x16, [x9]
        cmp     x3, x16
        b.le    fr_keep
        mov     x3, x16
fr_keep:
        mov     x0, x1
        bl      fs_slot
        mov     x11, x0                  # src
        mov     x12, x2                  # dst
        mov     x13, x3
        mov     x14, #0
fr_loop:
        cmp     x14, x13
        b.ge    fr_done
        ldrb    w15, [x11]
        strb    w15, [x12]
        add     x11, x11, #1
        add     x12, x12, #1
        add     x14, x14, #1
        b       fr_loop
fr_done:
        str     x13, [sp, #0]
        b       exc_ret
fr_bad:
        mov     x0, #1
        neg     x0, x0
        str     x0, [sp, #0]
        b       exc_ret

sys_fs_size:                            # x0 = id
        ldr     x1, [sp, #0]
        ldaddr  x9, fs_count
        ldr     x10, [x9]
        cmp     x1, x10
        b.ge    fr_bad
        ldaddr  x9, fs_len
        mov     x10, #8
        mul     x10, x1, x10
        add     x9, x9, x10
        ldr     x0, [x9]
        str     x0, [sp, #0]
        b       exc_ret

sys_fs_count:
        ldaddr  x9, fs_count
        ldr     x0, [x9]
        str     x0, [sp, #0]
        b       exc_ret

# exit：退出前校验 secret 与 **initrd 首字节**都没被用户改动。
# 只验"用户被拦了"不够 —— 拦了但值还是被改掉是另一类缺陷。
sys_exit:
        ldaddr  x20, msg_exit
        bl      puts
        ldr     x0, [sp, #0]
        bl      printdec
        mov     x9, #0
        movk    x9, #0x4040, lsl #16
        add     x9, x9, #2048           # 0x40400800 secret
        ldr     x10, [x9]
        mov     x11, #0xBEEF
        cmp     x10, x11
        b.ne    vbad
        mov     x9, #0
        movk    x9, #0x4041, lsl #16    # 0x40410000 = initrd
        ldrb    w10, [x9]
        mov     x11, #77                # 'M'（包字符串的首字节）
        cmp     x10, x11
        b.ne    vbad
        ldaddr  x20, msg_vok
        bl      puts
        b       halt
vbad:
        ldaddr  x20, msg_vbad
        bl      puts
        b       halt

exc_ret:
        ldp     x0, x1, [sp, #0]
        ldp     x2, x3, [sp, #16]
        ldp     x4, x5, [sp, #32]
        ldp     x6, x7, [sp, #48]
        ldp     x8, x9, [sp, #64]
        ldp     x10, x11, [sp, #80]
        ldp     x12, x13, [sp, #96]
        ldp     x14, x15, [sp, #112]
        ldp     x16, x17, [sp, #128]
        ldp     x18, x19, [sp, #144]
        ldp     x20, x21, [sp, #160]
        ldp     x22, x23, [sp, #176]
        ldp     x24, x25, [sp, #192]
        ldp     x26, x27, [sp, #208]
        ldp     x28, x29, [sp, #224]
        ldr     x30, [sp, #240]
        add     sp, sp, #256
        eret

puts:
        mov     x25, #0
        movk    x25, #0x0900, lsl #16
        mov     x26, x20
puts_loop:
        ldrb    w27, [x26]
        cmp     x27, #0
        b.eq    puts_ret
        strb    w27, [x25]
        add     x26, x26, #1
        b       puts_loop
puts_ret:
        ret

# printdec：x0 无符号十进制 + 换行（去掉前导 0）
printdec:
        mov     x25, #0
        movk    x25, #0x0900, lsl #16
        mov     x24, x0
        mov     x23, #1000000000
        mov     x19, #0
pd_loop:
        cmp     x23, #0
        b.eq    pd_end
        udiv    x22, x24, x23
        mul     x21, x22, x23
        sub     x24, x24, x21
        cmp     x22, #0
        b.ne    pd_emit
        cmp     x19, #0
        b.ne    pd_emit
        cmp     x23, #1
        b.ne    pd_skip
pd_emit:
        mov     x19, #1
        add     x22, x22, #48
        strb    w22, [x25]
pd_skip:
        mov     x21, #10
        udiv    x23, x23, x21
        b       pd_loop
pd_end:
        mov     x22, #10
        strb    w22, [x25]
        ret

halt:
        wfi
        b       halt

        .data
msg_boot:
        .asciz  "MO-PKG\n"
msg_pk:
        .asciz  "PK n="
msg_bad:
        .asciz  "BAD "
msg_err:
        .asciz  "E-"
msg_exit:
        .asciz  "EXIT "
msg_pf:
        .asciz  "PF"
msg_trf:
        .asciz  "TR"
msg_vok:
        .asciz  "V OK\n"
msg_vbad:
        .asciz  "V BAD\n"
msg_unknown:
        .asciz  "UNK\n"

        .bss
faultn:
        .zero   8
segs:
        .zero   128
fs_names:
        .zero   64
fs_len:
        .zero   64
fs_count:
        .zero   8
        .zero   4096
ustack_top:
