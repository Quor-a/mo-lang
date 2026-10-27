# a64exec —— 自举 aarch64 的 **ELF 加载器**：运行内核之外的程序
#
# 与 a64mmu / a64irq 的差别，正是"有用户空间"和"没有用户空间"的差别：
# 前面几版里被运行的"用户代码"是**链接进内核镜像**的一段，内核和它本来
# 就是同一个可执行文件的两部分。这一版被运行的东西来自内核之外 —— 由
# a64as + a64ld --base 独立生成的另一个 ELF，经 --initrd 铺到物理内存，
# 内核解析它的程序头、复制 PT_LOAD、清零 bss、然后 eret 进去。
#
# 所以"用户空间"在这里第一次有了可验证的含义：
#   内核跑的东西不是它自己的一部分，而是外部提供的可执行文件。
#
# 布局（每块 2MB）：
#   0x40000000  block0  AP=00  内核代码/数据（EL0 一律 abort）
#   0x40200000  block1  AP=01  用户区：用户程序的 text/data/bss/栈
#   0x40400000  block2  AP=00  内核私有：栈、页表、secret、**initrd 镜像**
#   0x40600000  block3  未映射 —— EL0 访问是转换错误
#
# initrd 放在内核私有块（0x40410000）是刻意的：用户程序若能读到它，
# 就能读到还没被加载的东西 —— 那等于没有隔离。
#
# 期望输出（见 tools/a64exectest.sh）：
#   MO-EXEC / U1 / 5050 / B= / 0 / PF2 / D / EXIT 7 / V OK

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

        # 污染用户区：把 [0x40200000, 0x40210000) 填成 0xA5A5A5A5。
        # 不做这一步，"加载器有没有清零 bss"根本测不出来 —— 模拟器里
        # 用户区本来就是全 0，不清零用户读到的也是 0，判据恒绿。
        # 这是本项目的老教训：样本看着充分，覆盖却是空的。
        bl      poison

        mov     x0, #0
        movk    x0, #0x4041, lsl #16    # 0x40410000 = initrd
        bl      load_elf
        cmp     x0, #0
        b.lt    load_fail
        msr     elr_el1, x0
        mov     x1, #0                  # PSTATE = 0 → EL0t
        msr     spsr_el1, x1
        eret

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
        #
        # 这里**不能**设成 AP=00（EL0 无权）。模拟器用页级 mem_protect 模拟
        # MMU，同一页在 EL0/EL1 只能是同一种权限：内核块一旦在 EL0 视图里
        # 没有 X，svc 陷入后**内核自己也取不到指**，症状是
        # UC_ERR_FETCH_PROT 且 PC 落在向量表 —— 极易被误读成"向量表建错"。
        # 真硬件按异常级分别判权，没有这个限制。
        # 所以内核的**秘密**放在 block2（AP=00），不放这里。
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
        # L2_ram[2] → 0x40400000 内核私有（含 initrd）：AP=00、UXN=1
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

# ── load_elf：x0 = 镜像基址，返回 x0 = entry（成功）或负错误码 ──
#   -1 magic   -2 非 ET_EXEC  -3 机器不是 aarch64  -4 phentsize≠56
#   -5 phnum 越界  -6 entry 不在用户区  -7 段越界  -8 没有 PT_LOAD
# 八种失败必须是**八个不同的码**：统一返回 -1 的话，调用方分不清
# "文件坏了"和"架构不对"，而这两件事该做的反应完全不同。
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
        # 本汇编器的 ldr/str 偏移按 8 缩放，读不到 18 / 54 这类非 8 倍数的
        # 偏移（ldrh 也一样）。所以按 8 字节对齐读、再移位取半字 ——
        # e_type@16 与 e_machine@18 同在 [16,24)，e_phentsize@54 在 [48,56)。
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
        # [x18] —— 于是整段只填了第一个字节，用户第一条指令就成了未定义
        # 指令（Unicorn 报 UDEF），而加载器自己认为一切正常。
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
        movk    x9, #0x4040, lsl #16
        movk    x9, #0x4041, lsl #16    # 0x40410000 = initrd
        ldrb    w10, [x9]
        mov     x11, #127
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
        .asciz  "MO-EXEC\n"
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
        .zero   4096
ustack_top:
