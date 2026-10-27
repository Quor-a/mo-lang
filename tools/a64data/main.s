# main.s —— 分派表演示：跳转表在 .data 里，表项指向**别的模块**的函数
#   .quad h0, h1  →  8 个占位字节 + .rela.data（R_AARCH64_ABS64 = 257）
#   链接器按规范把绝对地址写回去，_start 再 blr 间接调用
        .text
        .globl _start
        .globl h0
_start:
        adrp    x0, m_welcome
        addlo   x0, x0, m_welcome
        bl      puts

        adrp    x1, jt
        addlo   x1, x1, jt
        ldr     x2, [x1]
        blr     x2
        mov     x5, x0
        ldr     x2, [x1, #8]
        blr     x2
        add     x5, x5, x0

        mov     x9, #3
        cmp     x5, x9
        b.ne    bad
        adrp    x0, m_ok
        addlo   x0, x0, m_ok
        bl      puts
        b       next
bad:
        adrp    x0, m_bad
        addlo   x0, x0, m_bad
        bl      puts
next:
halt:
        wfi
        b       halt

# 0 号服务：打印 A，返回 1
h0:
        mov     x6, x30
        adrp    x0, m_a
        addlo   x0, x0, m_a
        bl      puts
        mov     x30, x6
        mov     x0, #1
        ret

        .data
# 4096 个填充字节不是装饰：没有它 text 与 data 落在同一页，adrp 的页偏移
# 恒为 0 —— "页对齐算错"这类变异根本进不了被测路径（测试全绿 = 没验到）。
        .zero 4096
m_welcome: .asciz "MO-SYS\n"
m_ok:   .asciz "SYS OK\n"
m_bad:  .asciz "SYS FAIL\n"
m_a:    .asciz "A\n"
        .align 8
jt:     .quad h0, h1
