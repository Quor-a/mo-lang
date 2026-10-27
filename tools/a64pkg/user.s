# a64pkg 的**用户程序**：内核之外的一个独立 ELF，通过 svc 使用内核的文件系统。
#
# 它是"包"里装的东西 —— 由 a64ld --base 0x40200000 独立链接，打包成可打印
# 字节串经 initrd 送进内核，内核解包、校验、再加载执行。
#
# 用户只能通过 svc 碰文件：文件的**内容**放在内核私有块（0x40430000），
# 用户直接读它会被页表拦下（data abort，块号 2）。这正是"文件由内核保管"
# 与"用户自己有块内存"的区别。
#
# 期望输出（见 tools/a64pkgtest.sh）：
#   U1 / 5050 / 0 / 8 / 8 / 5050 / 1 / 0 / PF2 / D / EXIT 7 / V OK
#   5050 = sum 1..100；0 = create 返回的 id；8/8 = 写入与读回的字节数；
#   第二个 5050 = 从文件读回的值（证明往返）；1 = 文件数。

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
        # create "out" —— 期望 id = 0
        ldaddr  x0, u_name
        mov     x1, #3
        mov     x8, #200               # sys_fs_create
        svc     #0
        mov     x21, x0
        mov     x1, x21
        mov     x8, #65
        svc     #0
        # write：把 5050 写进文件，8 字节
        ldaddr  x1, u_buf
        str     x19, [x1]
        mov     x0, x21
        ldaddr  x1, u_buf
        mov     x2, #8
        mov     x8, #201               # sys_fs_write
        svc     #0
        mov     x1, x0
        mov     x8, #65
        svc     #0                     # 期望 8
        # read：读回 8 字节
        mov     x0, x21
        ldaddr  x1, u_buf2
        mov     x2, #8
        mov     x8, #202               # sys_fs_read
        svc     #0
        mov     x1, x0
        mov     x8, #65
        svc     #0                     # 期望 8
        # 读回的值必须是 5050
        ldaddr  x1, u_buf2
        ldr     x1, [x1]
        mov     x8, #65
        svc     #0                     # 期望 5050
        # 文件数 —— 期望 1
        mov     x8, #204               # sys_fs_count
        svc     #0
        mov     x1, x0
        mov     x8, #65
        svc     #0
        # bss 必须是 0：内核在加载前把整块用户区污染成 0xA5A5A5A5，
        # 只有"按 p_memsz 清零"这一步做对了，这里才会读到 0。
        ldaddr  x1, u_scratch
        ldr     x1, [x1]
        mov     x8, #65
        svc     #0
        # 直接读文件**内容区**（在内核私有块）→ 必须触发 data abort
        mov     x21, #0
        movk    x21, #0x4043, lsl #16
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
u_done:
        .asciz  "D\n"
u_name:
        .asciz  "out"

        .bss
u_buf:
        .zero   8
u_buf2:
        .zero   8
u_scratch:
        .zero   8
