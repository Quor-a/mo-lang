# handlers.s —— 1 号服务 + UART 输出（都在**另一个**模块里）
        .text
        .globl puts
        .globl h1
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
h1:
        mov     x6, x30
        adrp    x0, m_b
        addlo   x0, x0, m_b
        bl      puts
        mov     x30, x6
        mov     x0, #2
        ret

        .data
m_b:    .asciz "B\n"
