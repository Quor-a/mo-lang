# main.s —— 只调用 fna，不直接引用 fnb、fnz
        .text
        .globl _start
_start:
        bl      fna
        adrp    x0, m_boot
        addlo   x0, x0, m_boot
        bl      puts
        adrp    x0, m_ok
        addlo   x0, x0, m_ok
        bl      puts
halt:
        wfi
        b       halt

        .data
m_boot: .asciz "MO-AR\n"
m_ok:   .asciz "SYS OK\n"
