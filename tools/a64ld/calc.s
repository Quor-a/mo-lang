# calc.s —— 独立模块：addnum(1..n 求和) + getmsg（引用**本模块**的 data）
        .text
        .globl addnum
        .globl getmsg
addnum:
        mov     x1, #0
        mov     x2, #0
addnum_loop:
        add     x2, x2, x1
        add     x1, x1, #1
        cmp     x1, x0
        b.le    addnum_loop
        mov     x0, x2
        ret
getmsg:
        adrp    x0, cmsg
        addlo   x0, x0, cmsg
        ret

        .data
cmsg:   .asciz "CALC\n"
