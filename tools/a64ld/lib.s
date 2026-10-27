# lib.s —— 独立模块：只提供 puts（往 UART 写字符串）
        .text
        .globl puts
puts:
        mov     x2, #0
        movk    x2, #0x0900, lsl #16
puts_loop:
        ldrb    w3, [x0]
        cmp     w3, #0
        b.eq    puts_done
        strb    w3, [x2]
        add     x0, x0, #1
        b       puts_loop
puts_done:
        ret
