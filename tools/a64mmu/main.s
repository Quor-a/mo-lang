# a64mmu —— 自举 aarch64 的 **MMU**：隔离由页表说了算，不再靠"约定"
#
# 与 a64svc 的差别：svc 版里"用户碰不到内核"是模拟器的约定；这一版，
# 能不能碰由页表描述符的 AP[2:1] / UXN 决定 —— 用户访问内核私有页会
# 真触发 **data abort**（EC=0x24），内核从 esr_el1 / far_el1 读原因。
#
# 页表格式是 AArch64 的**规范格式**（4KB granule、T0SZ=25、39 位 VA、
# 二级 2MB block），模拟器的判权限逻辑按 ARM ARM 遍历同一张表 ——
# 不是"内核和模拟器约好的私有结构"。
#
# 布局（每块 2MB）：
#   0x40000000  block0  AP=01  内核代码/数据/用户栈（EL0 可读可写可执行）
#   0x40200000  block1  AP=11  只读数据（EL0 可读、写则 abort）
#   0x40400000  block2  AP=00  内核私有：栈、秘密值、页表（EL0 一律 abort）
#   0x40600000  block3  未映射 —— EL0 访问是**转换错误**，与权限错误同类不同码
#
# 期望输出（见 tools/a64mmutest.sh）：
#   MO-MMU / U OK / R OK / PF1 / PF2 / PF2 / TR3 / UDONE / DONE / V OK / N4

        .text
        .globl _start
_start:
        # 内核栈放在**内核私有块**里（0x40401000）：连它自己都只有 EL1 能碰
        mov     x0, #0
        movk    x0, #0x4040, lsl #16
        add     x0, x0, #2048
        add     x0, x0, #2048           # 0x40401000
        msr     sp_el1, x0
        ldaddr  x0, vectors
        msr     vbar_el1, x0
        ldaddr  x0, ustack_top
        msr     sp_el0, x0
        ldaddr  x20, msg_boot
        bl      puts
        bl      build_pt
        bl      enable_mmu

        # 内核先自己写一篇：证明映射是通的（此时用户还没起来）
        mov     x9, #0
        movk    x9, #0x4040, lsl #16
        add     x9, x9, #2048           # 0x40400800 = secret
        mov     x10, #0xBEEF
        str     x10, [x9]
        mov     x10, #0
        movk    x10, #0x4020, lsl #16   # 0x40200000 = 只读数据
        mov     x11, #0x1234
        str     x11, [x10]

        ldaddr  x0, user_main
        msr     elr_el1, x0
        mov     x0, #0                  # PSTATE = 0 → EL0t
        msr     spsr_el1, x0
        eret

# ── 建页表 ──
# L1[0] → L2_dev（VA 0x0–0x3FFFFFFF，含 UART）；L1[1] → L2_ram（0x40000000 起）
# 表描述符 = 下一级地址 | 3（bit1:0 = 11）；block 描述符 = PA | 属性 | 1
build_pt:
        mov     x11, #0
        movk    x11, #0x4040, lsl #16
        add     x11, x11, #2048
        add     x11, x11, #2048         # 0x40402000 = L1
        mov     x13, #0
        movk    x13, #0x4040, lsl #16
        add     x13, x13, #2048
        add     x13, x13, #2048
        add     x13, x13, #2048         # 0x40403000 = L2_dev
        mov     x14, #0
        movk    x14, #0x4040, lsl #16
        add     x14, x14, #2048
        add     x14, x14, #2048
        add     x14, x14, #2048
        add     x14, x14, #2048         # 0x40404000 = L2_ram
        add     x9, x13, #3
        str     x9, [x11, #0]
        add     x9, x14, #3
        str     x9, [x11, #8]

        # L2_dev[72] → UART 0x09000000：设备内存(AttrIndx=1)，EL1 独享
        mov     x9, #0x0405
        movk    x9, #0, lsl #16
        movk    x9, #0x0900, lsl #32
        movk    x9, #0x0060, lsl #48    # AF|AP=00|UXN|PXN|device|valid
        str     x9, [x13, #576]         # 72 * 8

        # L2_ram[0] → 0x40000000：AP=01（EL0 可读写）、UXN=0（可执行）
        mov     x9, #0x0441
        movk    x9, #0, lsl #16
        movk    x9, #0x4000, lsl #32
        movk    x9, #0x0020, lsl #48
        str     x9, [x14, #0]
        # L2_ram[1] → 0x40200000：AP=11（EL0 只读）、UXN=1
        mov     x9, #0x04C1
        movk    x9, #0, lsl #16
        movk    x9, #0x4020, lsl #32
        movk    x9, #0x0040, lsl #48
        str     x9, [x14, #8]
        # L2_ram[2] → 0x40400000：AP=00（EL0 无权）、UXN=1
        mov     x9, #0x0401
        movk    x9, #0, lsl #16
        movk    x9, #0x4040, lsl #32
        movk    x9, #0x0040, lsl #48
        str     x9, [x14, #16]
        # L2_ram[3] → 未映射（保持 0）：EL0 访问 = 转换错误
        ret

enable_mmu:
        mov     x9, #0
        movk    x9, #0x4040, lsl #16
        add     x9, x9, #2048
        add     x9, x9, #2048           # L1 = 0x40402000
        msr     ttbr0_el1, x9
        mov     x9, #0x3519             # T0SZ=25（39 位 VA）+ 内外 WB
        msr     tcr_el1, x9
        mov     x9, #255                # attr0 = 0xFF 普通内存，attr1 = 0 设备
        msr     mair_el1, x9
        dsb
        isb
        mov     x9, #0x1005             # M=1（开 MMU）+ C + I
        msr     sctlr_el1, x9
        isb
        ret

# ── 异常向量表 ──
        .align  2048
vectors:
        .zero   1024
sync_lower:                             # 0x400：来自 lower EL 的同步异常
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
        lsr     x1, x0, #26             # EC
        mov     x2, #21                 # 0x15 = SVC
        cmp     x1, x2
        b.eq    do_svc
        mov     x2, #36                 # 0x24 = data abort from lower EL
        cmp     x1, x2
        b.eq    do_dabt
        ldaddr  x20, msg_unknown
        bl      puts
        b       halt

# ── data abort：这才是 MMU 起作用的地方 ──
# esr_el1 低 6 位是 DFSC：0xC–0xF 是权限错误，0x4–0x7 是转换错误。
# 两类都打印，但**必须打印不同的前缀** —— 只打一个"PF"就分不清
# "页表没建"和"页表建了但不许碰"，而这两者的修法完全相反。
do_dabt:
        ldaddr  x9, faultn
        ldr     x10, [x9]
        add     x10, x10, #1
        str     x10, [x9]
        mrs     x0, esr_el1
        lsl     x10, x0, #58            # DFSC = esr & 63（本汇编器的
        lsr     x10, x10, #58           # and 只支持寄存器形式，用移位取低 6 位）
        mrs     x11, far_el1            # 出错的虚拟地址
        mov     x12, #12                # 0xC：权限错误的下界
        cmp     x10, x12
        b.ge    dabt_perm
        ldaddr  x20, msg_trf
        bl      puts
        b       dabt_blk
dabt_perm:
        ldaddr  x20, msg_pf
        bl      puts
dabt_blk:
        # 打出是哪一块出的错（VA >> 21 & 7）：'1' 只读页、'2' 内核私有
        # 页、'3' 未映射页 —— 只打"被拦了"的话，拦错页也照样通过。
        lsr     x10, x11, #21
        lsl     x10, x10, #61           # & 7
        lsr     x10, x10, #61
        add     x10, x10, #48
        mov     x25, #0
        movk    x25, #0x0900, lsl #16
        strb    w10, [x25]
        mov     x10, #10
        strb    w10, [x25]
        # data abort 的返回地址是**出错那条指令本身**，必须 +4 跳过，
        # 否则原地重来一次、再重来一次 —— 无限循环。
        mrs     x0, elr_el1
        add     x0, x0, #4
        msr     elr_el1, x0
        b       exc_ret

do_svc:
        ldr     x8, [sp, #64]
        mov     x9, #64
        cmp     x8, x9
        b.eq    sys_write
        mov     x9, #93
        cmp     x8, x9
        b.eq    sys_exit
        mov     x0, #38
        neg     x0, x0
        str     x0, [sp, #0]
        b       exc_ret

# write(fd, buf, len)：buf 必须落在用户块 [0x40000000, 0x40200000) 内
sys_write:
        ldr     x1, [sp, #8]
        ldr     x2, [sp, #16]
        mov     x9, #0
        movk    x9, #0x4000, lsl #16
        cmp     x1, x9
        b.lt    sw_bad
        mov     x9, #0
        movk    x9, #0x4020, lsl #16
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

# exit：退出前**校验三处都没被用户改动** —— 只验"用户被拦了"是不够的：
# 拦了但值还是被改掉（模拟器没真拦住）是另一类缺陷，两者必须分开验。
sys_exit:
        ldaddr  x20, msg_exit
        bl      puts
        mov     x9, #0
        movk    x9, #0x4040, lsl #16
        add     x9, x9, #2048           # 0x40400800 = secret
        ldr     x10, [x9]
        mov     x11, #0xBEEF
        cmp     x10, x11
        b.ne    vbad
        mov     x9, #0
        movk    x9, #0x4020, lsl #16    # 只读数据
        ldr     x10, [x9]
        mov     x11, #0x1234
        cmp     x10, x11
        b.ne    vbad
        ldaddr  x9, uvar
        ldr     x10, [x9]
        mov     x11, #0x5A5A
        cmp     x10, x11
        b.ne    vbad
        ldaddr  x20, msg_vok
        bl      puts
        ldaddr  x9, faultn
        ldr     x10, [x9]
        ldaddr  x20, msg_n
        bl      puts
        add     x10, x10, #48
        mov     x25, #0
        movk    x25, #0x0900, lsl #16
        strb    w10, [x25]
        mov     x10, #10
        strb    w10, [x25]
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

halt:
        wfi
        b       halt

# ── 用户态（EL0）──
user_main:
        ldaddr  x10, uvar
        mov     x11, #0x5A5A
        str     x11, [x10]
        ldr     x12, [x10]
        cmp     x12, x11
        b.eq    u_ok
        ldaddr  x20, umsg_bad
        bl      uputs
        b       u_done
u_ok:
        ldaddr  x20, umsg_uok
        bl      uputs

        # 读只读页：应当**成功**
        mov     x10, #0
        movk    x10, #0x4020, lsl #16
        ldr     x12, [x10]
        mov     x11, #0x1234
        cmp     x12, x11
        b.eq    r_ok
        ldaddr  x20, umsg_bad
        bl      uputs
        b       u_done
r_ok:
        ldaddr  x20, umsg_rok
        bl      uputs

        # 写只读页 → 权限错误（DFSC 0xC–0xF），块号 1。
        # 故意写一个**不同**的值：若没真被拦住，退出时的校验就会报 V BAD ——
        # "被拦了"和"拦了但值还是被改掉"是两类缺陷，必须能分开看出来。
        mov     x13, #0xBAD
        str     x13, [x10]

        # 读 / 写内核私有页（secret 就在那里）→ 权限错误，块号 2
        mov     x10, #0
        movk    x10, #0x4040, lsl #16
        add     x10, x10, #2048         # 0x40400800
        ldr     x12, [x10]
        mov     x13, #0xDEAD
        str     x13, [x10]

        # 读未映射页 → 转换错误（DFSC 0x4–0x7），块号 3
        mov     x10, #0
        movk    x10, #0x4060, lsl #16
        ldr     x12, [x10]

        ldaddr  x20, umsg_done
        bl      uputs
        mov     x0, #0
        mov     x8, #93
        svc     #0
u_done:
        b       u_done

uputs:
        mov     x1, x20
        mov     x2, #0
        mov     x3, x20
up_len:
        ldrb    w4, [x3]
        cmp     x4, #0
        b.eq    up_len_done
        add     x3, x3, #1
        add     x2, x2, #1
        b       up_len
up_len_done:
        mov     x0, #1
        mov     x8, #64
        svc     #0
        ret

        .data
msg_boot:
        .asciz  "MO-MMU\n"
msg_pf:
        .asciz  "PF"
msg_trf:
        .asciz  "TR"
msg_exit:
        .asciz  "DONE\n"
msg_vok:
        .asciz  "V OK\n"
msg_vbad:
        .asciz  "V BAD\n"
msg_n:
        .asciz  "N"
msg_unknown:
        .asciz  "UNK\n"
umsg_uok:
        .asciz  "U OK\n"
umsg_rok:
        .asciz  "R OK\n"
umsg_done:
        .asciz  "UDONE\n"
umsg_bad:
        .asciz  "U BAD\n"

        .bss
uvar:
        .zero   8
faultn:
        .zero   8
        .zero   4096
ustack_top:
