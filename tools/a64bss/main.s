# main.s —— .bss 端到端驱动：七个自检，每一条都能单独失败
        .text
        .globl _start
_start:
        adrp    x0, m_boot
        addlo   x0, x0, m_boot
        bl      puts

# ① acc 初始必须为 0（bss 零初始化）
        bl      bz_get
        cmp     x0, #0
        b.ne    zbad
        adrp    x0, m_zok
        addlo   x0, x0, m_zok
        bl      puts
        b       znext
zbad:
        adrp    x0, m_bad
        addlo   x0, x0, m_bad
        bl      puts
znext:
# ② buf[0] 初始必须为 0（若 bss 落在 .data 上，这里读到的是非零数据）
        bl      bf_probe
        cmp     x0, #0
        b.ne    pbad
        adrp    x0, m_pok
        addlo   x0, x0, m_pok
        bl      puts
        b       pnext
pbad:
        adrp    x0, m_bad
        addlo   x0, x0, m_bad
        bl      puts
pnext:
# ③ 用 bss 里的 acc 累加 1..100
        bl      bz_zero
        mov     x8, #1
sum_loop:
        mov     x0, x8
        bl      bz_add
        add     x8, x8, #1
        mov     x9, #101
        cmp     x8, x9
        b.ne    sum_loop
        bl      bz_get
        mov     x9, #5050
        cmp     x0, x9
        b.eq    sok
        adrp    x0, m_bad
        addlo   x0, x0, m_bad
        bl      puts
        b       snext
sok:
        adrp    x0, m_sok
        addlo   x0, x0, m_sok
        bl      puts
snext:
# ④ 填充 12288 字节后，buf[0] 必须是 0xA5
        bl      bf_fill
        bl      bf_first
        cmp     x0, #165
        b.eq    fok
        adrp    x0, m_bad
        addlo   x0, x0, m_bad
        bl      puts
        b       fnext
fok:
        adrp    x0, m_fok
        addlo   x0, x0, m_fok
        bl      puts
fnext:
# ⑤ 填充之后 .data 里的字符串必须仍然完好
        adrp    x0, m_data
        addlo   x0, x0, m_data
        bl      puts
# ⑥ 填充之后另一个模块的 bss 变量仍是 5050（两个 bss 不重叠）
        bl      bz_get
        mov     x9, #5050
        cmp     x0, x9
        b.eq    aok
        adrp    x0, m_bad
        addlo   x0, x0, m_bad
        bl      puts
        b       anext
aok:
        adrp    x0, m_aok
        addlo   x0, x0, m_aok
        bl      puts
anext:
halt:
        wfi
        b       halt

        .data
# 4096 个填充字节不是装饰：没有它 text 与 data 落在同一页，adrp 的页偏移
# 恒为 0，"页对齐算错"这类变异根本进不了被测路径（测试全绿 = 没验到）。
        .zero 4096
m_boot: .asciz "MO-BSS\n"
m_zok:  .asciz "Z OK\n"
m_pok:  .asciz "P OK\n"
m_sok:  .asciz "SUM OK\n"
m_fok:  .asciz "FILL OK\n"
m_data: .asciz "DATA OK\n"
m_aok:  .asciz "ACC OK\n"
m_bad:  .asciz "BAD\n"
