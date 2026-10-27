# a64exec 的**用户程序**：由 a64as + a64ld --base 独立生成的另一个 ELF。
#
# 它是"内核之外"的东西 —— 内核镜像里没有它的任何一条指令。判据（见
# tools/a64exectest.sh）里"改它的一个字节，输出就变"正是为此存在。
#
# 用户程序只能通过 svc 请求内核：直接写 UART 会被丢掉，读内核私有块
# 会被页表拦下（data abort）。

        .text
        .globl _start
_start:
        ldaddr  x20, u_hello
        bl      uputs
        # sum 1..100 —— 期望 5050
        mov     x19, #0
        mov     x20, #1
uloop:
        cmp     x20, #101
        b.ge    udone
        add     x19, x19, x20
        add     x20, x20, #1
        b       uloop
udone:
        mov     x1, x19
        mov     x8, #65                # sys_putdec
        svc     #0
        # bss 必须是 0：内核在加载前把整块用户区污染成 0xA5A5A5A5，
        # 只有"按 p_memsz 清零"这一步做对了，这里才会读到 0。
        ldaddr  x20, u_beq
        bl      uputs
        ldaddr  x1, u_scratch
        ldr     x1, [x1]
        mov     x8, #65
        svc     #0
        # 读内核私有块（initrd 就在那里）→ 应触发 data abort，块号 2
        mov     x21, #0
        movk    x21, #0x4040, lsl #16
        ldr     x22, [x21]
        ldaddr  x20, u_done
        bl      uputs
        mov     x0, #7
        mov     x8, #93                # sys_exit
        svc     #0

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
        mov     x8, #64                # sys_write
        svc     #0
        ret

        .data
u_hello:
        .asciz  "U1\n"
u_beq:
        .asciz  "B=\n"
u_done:
        .asciz  "D\n"

        .bss
u_scratch:
        .zero   64
