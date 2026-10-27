# a64irq —— 自举 aarch64 的 **抢占式多任务** + **指令中止**
#
# 这是 a64mmu 的下一半。mmu 版里"用户碰不到内核"只验了**取数**（data abort，
# EC=0x24）；这一版补上**取指**（instruction abort，EC=0x20）—— 没有它的时候
# 用户 br 进内核地址会让模拟器直接报取指错误，那是"模拟器挂了"，不是
# "内核拦住了"。
#
# 再就是抢占：定时器 IRQ 从 EL0 打断 → VBAR + 0x480 → 内核保存现场到 PCB
# → 轮转到下一个任务 → eret 回去。三个任务轮流跑，证据是输出**交织**。
#
# 内存布局（每块 2MB，与 a64mmu 一致）：
#   0x40000000  AP=01 UXN=0  内核代码/数据 + 用户代码 + 用户栈
#   0x40200000  AP=11 UXN=1  只读数据
#   0x40400000  AP=00 UXN=1  内核私有：栈、页表、PCB、secret
#   0x40600000  未映射        —— 取指到这里是**转换**错误，与权限错误同类不同码
#
# 内核私有块内部（避开内核栈，栈从 0x40401800 向下长，不能压到 PCB）：
#   0x40400800 secret   0x40400900 cur   0x40400908 nsw
#   0x40400A00/0C00/0E00  PCB0/1/2（各 512B）   0x40401800 内核栈顶
#   0x40402000 L1  0x40403000 L2_dev  0x40404000 L2_ram
#
# PCB 偏移：0..247 = x0..x30   248 = sp_el0   256 = pc   264 = state
#
# 期望输出（见 tools/a64irqtest.sh）：
#   MO-IRQ / A0 B0 C0 A1 B1 ...（交织）/ IP / IT / ALLDONE

        .text
        .globl  _start
_start:
        mov     x0, #0
        movk    x0, #0x4040, lsl #16
        add     x0, x0, #2048
        add     x0, x0, #2048
        add     x0, x0, #2048           # 0x40401800 = 内核栈顶
        msr     sp_el1, x0
        ldaddr  x0, vectors
        msr     vbar_el1, x0
        ldaddr  x20, msg_boot
        bl      puts
        bl      init_gic
        bl      build_pt
        bl      enable_mmu
        mov     x9, #0
        movk    x9, #0x4040, lsl #16
        add     x9, x9, #2048           # 0x40400800 = secret
        mov     x10, #0xBEEF
        str     x10, [x9]
        bl      init_tasks
        b       start_cur

# ── GIC：开总开关 + 使能 30 号（虚拟定时器）──
init_gic:
        mov     x9, #0
        movk    x9, #0x0800, lsl #16    # GICD_CTLR
        mov     x10, #1
        str     x10, [x9]
        mov     x10, #1
        lsl     x10, x10, #30           # 1 << 30
        mov     x11, #0
        movk    x11, #0x0800, lsl #16
        add     x11, x11, #256          # GICD_ISENABLER0 = 0x08000100
        str     x10, [x11]
        ret

# ── 建页表（与 a64mmu 同构）──
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

        mov     x9, #0x0405
        movk    x9, #0, lsl #16
        movk    x9, #0x0900, lsl #32
        movk    x9, #0x0060, lsl #48    # UART：device、AP=00、UXN
        str     x9, [x13, #576]

        mov     x9, #0x0441
        movk    x9, #0, lsl #16
        movk    x9, #0x4000, lsl #32
        movk    x9, #0x0020, lsl #48    # block0：AP=01、UXN=0（用户可执行）
        str     x9, [x14, #0]
        mov     x9, #0x04C1
        movk    x9, #0, lsl #16
        movk    x9, #0x4020, lsl #32
        movk    x9, #0x0040, lsl #48    # block1：AP=11、UXN=1（只读）
        str     x9, [x14, #8]
        mov     x9, #0x0401
        movk    x9, #0, lsl #16
        movk    x9, #0x4040, lsl #32
        movk    x9, #0x0040, lsl #48    # block2：AP=00、UXN=1（内核私有）
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

# ── PCB 基址：x9 = 任务号 → x12 ──
pcb_base:
        # **临时寄存器只能用 x16/x17**：这里原来用 x13 装 512，而 x13 正是
        # init_one 传进来的任务入口 —— 于是 PCB[].pc 被写成 512，eret 跳到
        # 0x200，模拟器报 Invalid memory mapping。症状看着像页表/内存布局错，
        # 其实是寄存器约定：被调用函数毁了调用者还没用完的参数。
        mov     x12, #0
        movk    x12, #0x4040, lsl #16
        add     x12, x12, #2048
        add     x12, x12, #256
        add     x12, x12, #256          # 0x40400A00 = PCB0
        mov     x16, #512
        mul     x17, x9, x16
        add     x12, x12, x17
        ret

cur_addr:
        mov     x11, #0
        movk    x11, #0x4040, lsl #16
        add     x11, x11, #2048
        add     x11, x11, #256          # 0x40400900
        ret

# ── 初始化一个任务：x9 = id, x13 = 入口, x15 = 栈顶 ──
init_one:
        # **必须自己保存 LR**：init_one 是被 bl 调进来的，而它里面又要
        # `bl pcb_base` —— 第二次 bl 会把 x30 覆盖成自己的返回地址，于是
        # 结尾的 ret 跳回 init_one 内部，死循环在 0x1ac..0x1d4 上。
        # 症状是"跑满步数、只打印了 MO-IRQ"，看着像调度器根本没启动。
        sub     sp, sp, #16
        str     x30, [sp, #0]
        bl      pcb_base
        mov     x14, x12
        add     x14, x14, #256
        str     x13, [x14]
        mov     x14, x12
        add     x14, x14, #248
        str     x15, [x14]
        mov     x16, #1
        mov     x14, x12
        add     x14, x14, #264
        str     x16, [x14]
        ldr     x30, [sp, #0]
        add     sp, sp, #16
        ret

init_tasks:
        sub     sp, sp, #16
        str     x30, [sp, #0]
        mov     x9, #0
        ldaddr  x13, task_a
        ldaddr  x15, ustack_a
        bl      init_one
        mov     x9, #1
        ldaddr  x13, task_b
        ldaddr  x15, ustack_b
        bl      init_one
        mov     x9, #2
        ldaddr  x13, task_c
        ldaddr  x15, ustack_c
        bl      init_one
        bl      cur_addr
        mov     x9, #0
        str     x9, [x11]
        ldr     x30, [sp, #0]
        add     sp, sp, #16
        ret

# ── 首次启动当前任务 ──
start_cur:
        bl      cur_addr
        ldr     x9, [x11]
        bl      pcb_base
        mov     x13, x12
        add     x13, x13, #248
        ldr     x14, [x13]
        msr     sp_el0, x14
        mov     x13, x12
        add     x13, x13, #256
        ldr     x14, [x13]
        msr     elr_el1, x14
        mov     x0, #0
        msr     spsr_el1, x0
        eret

# ── 向量表 ──
        .align  2048
vectors:
        .zero   1024
sync_lower:                             # 0x400：来自 EL0 的同步异常
        b       exc_entry
        .zero   124
irq_lower:                              # 0x480：来自 EL0 的 IRQ（抢占入口）
        b       irq_entry
        .zero   124

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
        mov     x2, #32                 # 0x20 = instruction abort
        cmp     x1, x2
        b.eq    do_iabt
        mov     x2, #36                 # 0x24 = data abort
        cmp     x1, x2
        b.eq    do_dabt
        ldaddr  x20, msg_unk
        bl      puts
        b       halt

# ── 抢占入口：定时器 IRQ ──
irq_entry:
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
        # 读 IAR：不是 30 号就是伪中断，直接返回（不切换）。
        # **必须用 32 位访问**（ldr w10）：GIC 的寄存器都是 32 位的，
        # 用 ldr x10 会顺带把**下一个**寄存器（正好是 EOIR）读进来 ——
        # 第一次 EOIR 还是 0 所以看不出来，第二次就变成 0x1E0000001E，
        # 于是 cmp 失败、不再应答，in_irq 永远为真，此后再无中断。
        # 这是"第一次对、第二次错"的状态残留，只跑一遍是发现不了的。
        mov     x9, #0x000C
        movk    x9, #0x0801, lsl #16    # GICC_IAR
        ldr     w10, [x9]
        mov     x11, #30
        cmp     x10, x11
        b.ne    exc_ret
        # 应答：写 EOIR。**必须写** —— 不写的话 in_irq 一直是真，
        # 下一次 IRQ 再也不会来，于是任务 A 独占跑完，输出毫无交织。
        mov     x9, #0x0010
        movk    x9, #0x0801, lsl #16    # GICC_EOIR
        str     w10, [x9]
        bl      cur_addr
        ldr     x9, [x11]
        bl      pcb_base
        bl      save_ctx
        # nsw++
        bl      cur_addr
        ldr     x10, [x11, #8]
        add     x10, x10, #1
        str     x10, [x11, #8]
        b       sched_next

# ── instruction abort：用户**跳进**不该执行的页 ──
do_iabt:
        mrs     x0, esr_el1
        lsl     x10, x0, #58            # IFSC = esr & 63（本汇编器的 and
        lsr     x10, x10, #58           # 只支持寄存器形式，用移位取低 6 位）
        mov     x11, #12                # 0xC：权限错误下界
        cmp     x10, x11
        b.ge    iabt_perm
        ldaddr  x20, msg_it             # 转换错误：跳到了没映射的地方
        bl      puts
        b       iabt_kill
iabt_perm:
        ldaddr  x20, msg_ip             # 权限错误：跳到了内核私有页（UXN/AP=00）
        bl      puts
iabt_kill:
        bl      kill_cur
        b       sched_next

do_dabt:
        ldaddr  x20, msg_da
        bl      puts
        bl      kill_cur
        b       sched_next

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

sys_exit:
        bl      kill_cur
        b       sched_next

# ── 杀掉当前任务 ──
kill_cur:
        sub     sp, sp, #16
        str     x30, [sp, #0]
        bl      cur_addr
        ldr     x9, [x11]
        bl      pcb_base
        mov     x13, #0
        mov     x14, x12
        add     x14, x14, #264
        str     x13, [x14]
        ldr     x30, [sp, #0]
        add     sp, sp, #16
        ret

# ── 轮转调度：找下一个活着的任务 ──
sched_next:
        bl      cur_addr
        ldr     x9, [x11]
        mov     x10, #0                 # 已尝试次数
sn_loop:
        add     x9, x9, #1
        mov     x13, #3
        cmp     x9, x13
        b.lt    sn_chk
        mov     x9, #0
sn_chk:
        bl      pcb_base
        mov     x13, x12
        add     x13, x13, #264
        ldr     x14, [x13]
        mov     x15, #1
        cmp     x14, x15
        b.eq    sn_found
        add     x10, x10, #1
        mov     x13, #3
        cmp     x10, x13
        b.lt    sn_loop
        b       all_done
sn_found:
        bl      cur_addr
        str     x9, [x11]
        bl      pcb_base
        bl      restore_ctx
        b       exc_ret

all_done:
        ldaddr  x20, msg_done
        bl      puts
        # secret 必须还在：整轮抢占下来内核私有页一次都没被用户碰到
        mov     x9, #0
        movk    x9, #0x4040, lsl #16
        add     x9, x9, #2048
        ldr     x10, [x9]
        mov     x11, #0xBEEF
        cmp     x10, x11
        b.ne    vbad
        ldaddr  x20, msg_vok
        bl      puts
        b       halt
vbad:
        ldaddr  x20, msg_vbad
        bl      puts
        b       halt

# ── 上下文：栈 ↔ PCB ──
save_ctx:                               # x12 = PCB：栈 → PCB
        mov     x14, #0
        mov     x18, #248               # 31 个寄存器 × 8
scl:
        cmp     x14, x18
        b.ge    scd
        mov     x16, sp
        add     x16, x16, x14
        ldr     x15, [x16]
        mov     x16, x12
        add     x16, x16, x14
        str     x15, [x16]
        add     x14, x14, #8
        b       scl
scd:
        mrs     x15, sp_el0
        mov     x16, x12
        add     x16, x16, #248
        str     x15, [x16]
        mrs     x15, elr_el1
        mov     x16, x12
        add     x16, x16, #256
        str     x15, [x16]
        ret

restore_ctx:                            # x12 = PCB：PCB → 栈
        mov     x14, #0
        mov     x18, #248
rcl:
        cmp     x14, x18
        b.ge    rcd
        mov     x16, x12
        add     x16, x16, x14
        ldr     x15, [x16]
        mov     x16, sp
        add     x16, x16, x14
        str     x15, [x16]
        add     x14, x14, #8
        b       rcl
rcd:
        mov     x13, x12
        add     x13, x13, #248
        ldr     x14, [x13]
        msr     sp_el0, x14
        mov     x13, x12
        add     x13, x13, #256
        ldr     x14, [x13]
        msr     elr_el1, x14
        ret

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

# ── 三个用户任务（EL0）──
# 每个任务一进来就在**自己的**栈顶写自己的标记，每轮循环读回来比对：
# 切换时若忘了换 sp_el0，三个任务会共用一个栈，标记互相覆盖 → 打印 SBAD。
task_a:
        mov     x20, #65                # 'A'
        # **期望值必须是链接期常量，不能从 sp 推导**：早先写 `mov x21, sp`，
        # 于是内核就算把栈设错了（比如忘了 msr sp_el0），x21 也跟着错，
        # cmp 照样相等 —— 判据形同虚设，"栈没切换"这个缺陷永远抓不到。
        ldaddr  x21, ustack_a            # 内核**应该**给我的那个栈
        mov     x19, #0
ta_loop:
        mov     x22, sp
        cmp     x22, x21
        b.ne    stack_bad
        mov     x23, #5
        cmp     x19, x23
        b.ge    ta_exit
        mov     x0, x20
        mov     x1, x19
        add     x1, x1, #48
        bl      uprint3
        bl      udelay
        add     x19, x19, #1
        b       ta_loop
ta_exit:
        mov     x0, #0
        mov     x8, #93
        svc     #0
        b       ta_exit

task_b:
        mov     x20, #66                # 'B'
        # **期望值必须是链接期常量，不能从 sp 推导**：早先写 `mov x21, sp`，
        # 于是内核就算把栈设错了（比如忘了 msr sp_el0），x21 也跟着错，
        # cmp 照样相等 —— 判据形同虚设，"栈没切换"这个缺陷永远抓不到。
        ldaddr  x21, ustack_b            # 内核**应该**给我的那个栈
        mov     x19, #0
tb_loop:
        mov     x22, sp
        cmp     x22, x21
        b.ne    stack_bad
        mov     x23, #4
        cmp     x19, x23
        b.ge    tb_atk
        mov     x0, x20
        mov     x1, x19
        add     x1, x1, #48
        bl      uprint3
        bl      udelay
        add     x19, x19, #1
        b       tb_loop
tb_atk:
        mov     x9, #0
        movk    x9, #0x4060, lsl #16    # 未映射块 → 取指**转换**错误
        br      x9

task_c:
        mov     x20, #67                # 'C'
        # **期望值必须是链接期常量，不能从 sp 推导**：早先写 `mov x21, sp`，
        # 于是内核就算把栈设错了（比如忘了 msr sp_el0），x21 也跟着错，
        # cmp 照样相等 —— 判据形同虚设，"栈没切换"这个缺陷永远抓不到。
        ldaddr  x21, ustack_c            # 内核**应该**给我的那个栈
        mov     x19, #0
tc_loop:
        mov     x22, sp
        cmp     x22, x21
        b.ne    stack_bad
        mov     x23, #2
        cmp     x19, x23
        b.ge    tc_atk
        mov     x0, x20
        mov     x1, x19
        add     x1, x1, #48
        bl      uprint3
        bl      udelay
        add     x19, x19, #1
        b       tc_loop
tc_atk:
        mov     x9, #0
        movk    x9, #0x4040, lsl #16    # 内核私有块 → 取指**权限**错误
        br      x9

stack_bad:
        mov     x0, x20                 # 先打自己的标记，才知道是哪个任务的栈坏了
        mov     x1, #66
        bl      uprint3
        mov     x0, #65
        mov     x1, #68
        bl      uprint3
        b       stack_bad

# **一次 svc 写完一整行**：逐字符写的话，抢占可以发生在两个字符之间，
# 于是输出变成 "BA3" "3" "AIT" 这种碎片 —— 那是抢占真的在工作，但对判据
# 很不友好。改成一次 write(3) 之后，行内不再被打断，交织只发生在行之间。
uprint3:                                # x0 = 字母, x1 = 数字字符
        ldaddr  x2, ubuf
        strb    w0, [x2]
        add     x2, x2, #1
        strb    w1, [x2]
        add     x2, x2, #1
        mov     x3, #10
        strb    w3, [x2]
        ldaddr  x1, ubuf
        mov     x2, #3
        mov     x8, #64
        svc     #0
        ret

udelay:
        mov     x0, #0
udl:
        add     x0, x0, #1
        mov     x1, #200
        cmp     x0, x1
        b.lt    udl
        ret

        .data
msg_boot:
        .asciz  "MO-IRQ\n"
msg_ip:
        .asciz  "IP\n"
msg_it:
        .asciz  "IT\n"
msg_da:
        .asciz  "DA\n"
msg_done:
        .asciz  "ALLDONE\n"
msg_vok:
        .asciz  "V OK\n"
msg_vbad:
        .asciz  "V BAD\n"
msg_unk:
        .asciz  "UNK\n"

        .bss
ubuf:
        .zero   8
        .zero   4096
ustack_a_bottom:
        .zero   4096
ustack_a:
ustack_b_bottom:
        .zero   4096
ustack_b:
ustack_c_bottom:
        .zero   4096
ustack_c:
