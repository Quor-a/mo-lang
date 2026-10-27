# b.s —— 归档成员 2：定义 fnb，被 a.s 引用
#   它自己不引用任何归档里的东西，所以只有"抽取循环迭代到第二轮"
#   时才会被拉进来。第一轮时 fnb 还不是 UNDEF（fna 都没进来），
#   probe(b.o) 必然返回 0。
        .text
        .globl fnb
fnb:
        sub     sp, sp, #16
        str     x30, [sp]
        adrp    x0, b_msg
        addlo   x0, x0, b_msg
        bl      puts
        ldr     x30, [sp]
        add     sp, sp, #16
        ret

        .data
b_msg:  .asciz "B\n"
