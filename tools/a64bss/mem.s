# mem.s —— 独立的 bss 使用者：累加器 acc 放在**本模块**的 .bss 里
#   链接器必须把它安排在 全部 .data 之后 + 本文件 bss 偏移 处。
#   若漏掉 FBW（本文件 bss 起点），acc 会落在模块 A 的 bss 起点上，
#   与另一个模块的 buf 重叠 —— 但**地址仍然合法、读出来也是 0**，
#   看不出错；只有两个模块互相写才暴露。
        .text
        .globl bz_zero
        .globl bz_add
        .globl bz_get
bz_zero:
        adrp    x1, acc
        addlo   x1, x1, acc
        mov     x2, #0
        str     x2, [x1]
        ret
bz_add:
        adrp    x1, acc
        addlo   x1, x1, acc
        ldr     x2, [x1]
        add     x2, x2, x0
        str     x2, [x1]
        ret
bz_get:
        adrp    x1, acc
        addlo   x1, x1, acc
        ldr     x0, [x1]
        ret

        .bss
        .align 8
acc:    .zero 8
