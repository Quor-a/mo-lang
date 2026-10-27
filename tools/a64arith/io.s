# io.s —— 打印与换行。由墨语言写的汇编器（examples/a64as.mo）汇编。
#
# 约定：x25 = UART 数据寄存器地址（0x09000000），全程不变。
# puts 只动 x26/x27；printdec 只动 x0-x3/x23/x24/x26/x27。

        .text
        .globl  puts
        .globl  printdec
        .globl  pnl

# puts：x20 = 字符串首址
puts:
        mov     x26, x20
puts_loop:
        ldrb    w27, [x26]
        cbz     x27, puts_ret
        strb    w27, [x25]
        add     x26, x26, #1
        b       puts_loop
puts_ret:
        ret

# printdec：x0 = 有符号整数，十进制打印（含负号）
#   除法用 udiv、取余用 msub —— 这两条错了，这里打出的每位都是错的。
printdec:
        mov     x26, x0
        cmp     x26, #0
        b.ge    pd_pos
        mov     x27, #45
        strb    w27, [x25]
        neg     x26, x26
pd_pos:
        ldaddr  x24, pbuf
        add     x24, x24, #24
        mov     x23, #0
pd_loop:
        mov     x0, x26
        mov     x1, #10
        udiv    x2, x0, x1
        msub    x3, x2, x1, x0
        add     x3, x3, #48
        sub     x24, x24, #1
        strb    w3, [x24]
        add     x23, x23, #1
        mov     x26, x2
        cbnz    x26, pd_loop
pd_out:
        ldrb    w27, [x24]
        strb    w27, [x25]
        add     x24, x24, #1
        subs    x23, x23, #1
        cbnz    x23, pd_out
        ret

pnl:
        mov     x27, #10
        strb    w27, [x25]
        ret

        .data
pbuf:       .zero 32
