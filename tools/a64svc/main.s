# a64svc —— 自举 aarch64 的**特权级分离**：EL1 内核 + EL0 用户 + svc 系统调用
#
# 下面没有 Linux、没有 libc、没有安卓：只有一块 CPU、一个 UART 和一张
# 异常向量表。每条指令的机器码都由墨语言写的汇编器（examples/a64as.mo）算出。
#
# 三条性质各自独立可验：
#   ① 用户只能通过 svc 请求服务。内核**校验用户指针**：越界指针被拒，
#      返回 -EFAULT —— 没有这一步，用户能借系统调用读到任意内核内存。
#   ② svc 的返回地址是**下一条**指令；被陷入的特权指令的返回地址是
#      **陷入的那条本身**。方向相反，混用会死循环或跳过一条指令。
#   ③ EL0 执行 msr/mrs/eret 被陷入（EC=0x18），且陷入发生在**执行之前**。

        .text
        .globl _start
_start:
        ldaddr  x0, kstack_top
        msr     sp_el1, x0              # 内核**自己的**栈（不是 mov sp）
        ldaddr  x0, vectors
        msr     vbar_el1, x0
        ldaddr  x0, ustack_top
        msr     sp_el0, x0
        ldaddr  x0, user_main
        msr     elr_el1, x0
        mov     x0, #0                  # PSTATE = 0 → EL0t
        msr     spsr_el1, x0
        eret                            # 落到 EL0 的 user_main

# ── 异常向量表：必须 2KB 对齐（VBAR 的硬件要求）──
# 未实现的向量填 0x00000000（udf #0），走错立刻炸，不会静默跑飞。
        .align  2048
vectors:
        .zero   1024                    # 0x000 .. 0x3FF
sync_lower:                             # 0x400：来自 lower EL 的同步异常
        b       exc_entry

# ── 内核：异常入口 ──
# 保存**全部**通用寄存器后才能随意使用它们 —— x19..x28 是 callee-saved，
# 只保存一部分会静默破坏用户状态（用户指望它们跨 svc 不变）。
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
        lsr     x1, x0, #26             # EC（异常类别）
        mov     x2, #21                 # 0x15 = SVC from AArch64
        cmp     x1, x2
        b.eq    do_svc
        mov     x2, #24                 # 0x18 = 被陷入的 MRS/MSR/系统指令
        cmp     x1, x2
        b.eq    do_trap
        ldaddr  x20, msg_unknown
        bl      puts
        b       halt

do_svc:
        ldr     x8, [sp, #64]           # 用户 x8 = 调用号
        mov     x9, #64                 # write
        cmp     x8, x9
        b.eq    sys_write
        mov     x9, #93                 # exit
        cmp     x8, x9
        b.eq    sys_exit
        mov     x9, #38                 # -ENOSYS（避免负立即数：先取正再 neg）
        neg     x0, x9
        str     x0, [sp, #0]
        b       exc_ret

# write(fd, buf, len)：内核必须校验用户指针落在 [ubase, uend) 之内。
sys_write:
        ldr     x1, [sp, #8]            # buf
        ldr     x2, [sp, #16]           # len
        ldaddr  x9, ubase
        cmp     x1, x9
        b.lt    sys_write_bad
        ldaddr  x10, uend
        cmp     x1, x10
        b.ge    sys_write_bad
        mov     x25, #0
        movk    x25, #0x0900, lsl #16   # UART 数据寄存器
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
sys_write_bad:
        mov     x9, #14                 # -EFAULT
        neg     x0, x9
        str     x0, [sp, #0]
        b       exc_ret

sys_exit:
        ldaddr  x20, msg_exit
        bl      puts
        b       halt

# 被陷入的特权指令：ELR 指向**陷入的那条**本身，必须 +4 才不会原地重来。
# 同时验证陷入发生在执行**之前** —— 所以 VBAR 应当仍是原来的值。
do_trap:
        ldaddr  x20, msg_trap
        bl      puts
        mrs     x9, vbar_el1
        ldaddr  x10, vectors
        cmp     x9, x10
        b.eq    trap_vbar_ok
        ldaddr  x20, msg_vbad
        bl      puts
        b       halt
trap_vbar_ok:
        ldaddr  x20, msg_vok
        bl      puts
        mrs     x0, elr_el1
        add     x0, x0, #4              # 跳过被陷入的那条指令
        msr     elr_el1, x0
        mov     x9, #1
        neg     x0, x9                  # 返回 -1
        str     x0, [sp, #0]
        b       exc_ret

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

# puts：x20 = 串首址；用 x25/x26/x27（它们已入栈，退出前会恢复）
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

# ── 用户态（EL0）：碰不到 UART，只能 svc ──
user_main:
        ldaddr  x20, umsg1
        bl      uputs
        ldaddr  x20, umsg_w
        bl      uputs

        # 自检二：越界指针必须被内核拒绝（返回 -EFAULT）
        ldaddr  x1, vectors             # 内核地址，不在用户区
        mov     x0, #1
        mov     x2, #4
        mov     x8, #64
        svc     #0
        mov     x9, #14
        neg     x9, x9
        cmp     x0, x9
        b.eq    u_ptr_ok
        ldaddr  x20, umsg_bad
        bl      uputs
        b       u_done
u_ptr_ok:
        ldaddr  x20, umsg_p
        bl      uputs

        # 自检三：EL0 执行特权指令 → 被陷入，返回 -1
u_done:
        ldaddr  x9, uend                # 故意写一个**不同**的值：
        msr     vbar_el1, x9            # 若这条真被执行，VBAR 就会变
        mov     x9, #1
        neg     x9, x9
        cmp     x0, x9
        b.eq    u_trap_ok
        ldaddr  x20, umsg_bad
        bl      uputs
        b       u_exit
u_trap_ok:
        ldaddr  x20, umsg_t
        bl      uputs

u_exit:
        # 自检四：EL0 写 tpidr_el1（MSR，sysreg 高位**顶进 bit20**）
        #   —— vbar_el1 落在 0xD51、它落在 0xD52；只认前者的话这条不拦，
        #      用户态照样能改系统寄存器，而只用 vbar 的 demo 测试全绿。
        ldaddr  x9, uend
        msr     tpidr_el1, x9
        mov     x9, #1
        neg     x9, x9
        cmp     x0, x9
        b.eq    u_m_ok
        ldaddr  x20, umsg_bad
        bl      uputs
        b       u_mrs
u_m_ok:
        ldaddr  x20, umsg_m
        bl      uputs

        # 自检五：EL0 读 esr_el1（MRS，落在 0xD54 —— 同样是高位分支）
u_mrs:
        mov     x10, #4660              # 0x1234 哨兵必须放在**目标**寄存器上：
        mrs     x10, esr_el1            # 放在别的寄存器里，mrs 真执行也看不出来
        mov     x11, #4660
        cmp     x10, x11
        b.ne    u_mrs_bad
        mov     x9, #1
        neg     x9, x9
        cmp     x0, x9                  # x0 应为 -1（被陷入）
        b.eq    u_r_ok
u_mrs_bad:
        ldaddr  x20, umsg_bad
        bl      uputs
        b       u_fin
u_r_ok:
        ldaddr  x20, umsg_r
        bl      uputs

u_fin:
        # 自检六：EL0 **直接**写 UART 必须无效 —— 硬件属于内核。
        # 若这条生效，输出里会平白多出一个 'X'（就在 U OK 前面）。
        mov     x12, #0
        movk    x12, #0x0900, lsl #16
        mov     x13, #88                 # 'X'
        strb    w13, [x12]
        ldaddr  x20, umsg_u
        bl      uputs

        mov     x0, #0
        mov     x8, #93                 # exit
        svc     #0
        b       u_fin

# uputs：x20 = 串首址，经 write 系统调用输出
uputs:
        mov     x26, x20
uputs_len:
        ldrb    w27, [x26]
        cmp     x27, #0
        b.eq    uputs_do
        add     x26, x26, #1
        b       uputs_len
uputs_do:
        sub     x2, x26, x20            # len
        mov     x1, x20
        mov     x0, #1                  # fd
        mov     x8, #64                 # write
        svc     #0
        ret

        .data
ubase:
umsg1:      .asciz "MO-SVC\n"
umsg_w:     .asciz "W OK\n"
umsg_p:     .asciz "P OK\n"
umsg_t:     .asciz "T OK\n"
umsg_m:     .asciz "M OK\n"
umsg_r:     .asciz "R OK\n"
umsg_u:     .asciz "U OK\n"
umsg_bad:   .asciz "BAD\n"
uend:

msg_trap:   .asciz "TRAP\n"
msg_vok:    .asciz "VBAR OK\n"
msg_vbad:   .asciz "VBAR BAD\n"
msg_unknown:.asciz "UNKNOWN\n"
msg_exit:   .asciz "EXIT\n"

        .bss
        .align  16
        .zero   4096
kstack_top:
        .align  16
        .zero   4096
ustack_top:
