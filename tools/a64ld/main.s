# main.s —— 引用 lib.s 的 puts、calc.s 的 addnum/getmsg
        .text
        .globl _start
_start:
        adrp    x0, m_boot
        addlo   x0, x0, m_boot
        bl      puts

        mov     x0, #100
        bl      addnum
        mov     x3, x0
        mov     x9, #5050
        cmp     x3, x9
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
        bl      getmsg
        bl      puts
halt:
        wfi
        b       halt

        .data
# 4096 个填充字节不是装饰：没有它，text 与 data 落在**同一页**内，
# adrp 算出的页偏移恒为 0 —— 于是"页对齐写错"这类变异根本进不了被测
# 路径（测试全绿 = 什么都没验到）。这是本项目第三例"样本充分 ≠ 覆盖充分"。
        .zero 4096
m_boot: .asciz "MO-LD BOOT\n"
m_ok:   .asciz "SUM=5050 OK\n"
m_bad:  .asciz "FAIL\n"
