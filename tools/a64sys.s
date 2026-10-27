# sys64 —— 由墨语言写的汇编器（examples/a64as.mo）直接汇编出的 aarch64 裸机系统
#
# 它下面没有 Linux、没有 libc、没有安卓：只有一块 CPU 和一个 UART。
# 机器码的每个字节都由墨语言程序算出来，不经过任何 C 编译器 / as / ld。

        .text
_start:
        mov     x25, #0
        movk    x25, #0x0900, lsl #16     # UART 数据寄存器 0x09000000
        ldaddr  x20, msg_boot
        bl      puts

        ldaddr  x21, stack_top
        mov     sp, x21

        # ── 自检一：1..100 求和 = 5050 ──
        mov     x0, #0
        mov     x1, #1
loop_sum:
        add     x0, x0, x1
        add     x1, x1, #1
        cmp     x1, #101
        b.lt    loop_sum
        mov     x9, #5050
        cmp     x0, x9
        b.ne    fail_sum
        ldaddr  x20, msg_sum
        bl      puts
        b       do_fib
fail_sum:
        ldaddr  x20, msg_bad
        bl      puts
        b       halt

        # ── 自检二：递归 fib(10) = 55（验证 bl/ret + 栈）──
do_fib:
        mov     x0, #10
        bl      fib
        cmp     x0, #55
        b.ne    fail_fib
        ldaddr  x20, msg_fib
        bl      puts
        b       do_mem
fail_fib:
        ldaddr  x20, msg_bad
        bl      puts
        b       halt

        # ── 自检三：内存写后读回 ──
do_mem:
        ldaddr  x22, sbuf
        mov     x23, #12345
        str     x23, [x22]
        ldr     x24, [x22]
        mov     x9, #12345
        cmp     x24, x9
        b.ne    fail_mem
        ldaddr  x20, msg_mem
        bl      puts
        b       do_imm
fail_mem:
        ldaddr  x20, msg_bad
        bl      puts
        b       halt

        # ── 自检四：movz 的 imm16 字段位置 ──
#   单独看"程序能跑"抓不到这个：源码里 movz 只装过 0 和 1，
#   移位写错的结果被求和循环抹平。必须让立即数值本身参与判据。
do_imm:
        movz    x28, #0x1234
        mov     x9, #4660            # == 0x1234
        cmp     x28, x9
        b.ne    fail_imm
        ldaddr  x20, msg_imm
        bl      puts
        b       halt
fail_imm:
        ldaddr  x20, msg_bad
        bl      puts
        b       halt

halt:
        wfi
        b       halt

# puts：x20 = 字符串首址；用 x25(UART) x26 x27，不动 x0-x24
puts:
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

# fib：x0 = n，返回 x0；递归，走栈
#   中间结果存栈不存寄存器：递归会覆盖调用者保存的寄存器
fib:
        cmp     x0, #2
        b.lt    fib_base
        sub     sp, sp, #32
        str     x30, [sp, #0]
        str     x0, [sp, #8]
        sub     x0, x0, #1
        bl      fib
        str     x0, [sp, #16]      # 中间结果必须放栈上：
        ldr     x0, [sp, #8]       # 放进寄存器会被内层 fib 覆盖（实测 fib 结果错）
        sub     x0, x0, #2
        bl      fib
        ldr     x10, [sp, #16]
        add     x0, x0, x10
        ldr     x30, [sp, #0]
        add     sp, sp, #32
        ret
fib_base:
        ret

        .data
msg_boot:   .asciz "MO-A64 BOOT\n"
msg_sum:    .asciz "SUM=5050 OK\n"
msg_fib:    .asciz "FIB=55 OK\n"
msg_mem:    .asciz "MEM OK\n"
msg_imm:    .asciz "IMM OK\n"
msg_bad:    .asciz "FAIL\n"
sbuf:       .zero 8
            .zero 4096
stack_top:
