# main.s —— 第二批算术 / 条件指令的裸机自检
#
# 每条都打印一个**具体数字**，期望由测试脚本独立算出。
# 只判"程序没崩"是抓不到字段错位的：指令照样合法、照样跑完。

        .text
        .globl  _start
_start:
        mov     x25, #0
        movk    x25, #0x0900, lsl #16     # UART
        ldaddr  x21, stack_top
        mov     sp, x21

        ldaddr  x20, m_boot
        bl      puts

        # ── T1 udiv：12345 / 100 = 123 ──
        ldaddr  x20, m_udiv
        bl      puts
        movz    x10, #0x3039              # 12345
        mov     x11, #100
        udiv    x12, x10, x11
        mov     x0, x12
        bl      printdec
        bl      pnl

        # ── T2 msub 取余：12345 - (12345/100)*100 = 45 ──
        ldaddr  x20, m_rem
        bl      puts
        udiv    x13, x10, x11
        msub    x14, x13, x11, x10
        mov     x0, x14
        bl      printdec
        bl      pnl

        # ── T3 sdiv：-12345 / 100 = -123（向零取整，不是向下）──
        ldaddr  x20, m_sdiv
        bl      puts
        mov     x15, #0
        sub     x15, x15, x10             # -12345
        sdiv    x12, x15, x11
        mov     x0, x12
        bl      printdec
        bl      pnl

        # ── T4 sdiv：12345 / -100 = -123 ──
        ldaddr  x20, m_sdiv2
        bl      puts
        mov     x16, #0
        sub     x16, x16, x11             # -100
        sdiv    x12, x10, x16
        mov     x0, x12
        bl      printdec
        bl      pnl

        # ── T5 lsr：1<<63 逻辑右移 63 位 = 1 ──
        ldaddr  x20, m_lsr
        bl      puts
        mov     x10, #1
        lsl     x10, x10, #63
        lsr     x12, x10, #63
        mov     x0, x12
        bl      printdec
        bl      pnl

        # ── T6 asr：同样一个数算术右移 63 位 = -1 ──
        #   lsr 与 asr 的区别全在 sf/opc 两位，值选 1<<63 才能把差异放大
        #   成 1 与 -1；随便取个小正数两条指令结果相同，测了等于没测。
        ldaddr  x20, m_asr
        bl      puts
        asr     x12, x10, #63
        mov     x0, x12
        bl      printdec
        bl      pnl

        # ── T7 asr：-16 >> 2 = -4 ──
        ldaddr  x20, m_asr2
        bl      puts
        mov     x10, #16
        neg     x10, x10
        asr     x12, x10, #2
        mov     x0, x12
        bl      printdec
        bl      pnl

        # ── T8 neg：-(42) = -42 ──
        ldaddr  x20, m_neg
        bl      puts
        mov     x10, #42
        neg     x12, x10
        mov     x0, x12
        bl      printdec
        bl      pnl

        # ── T9 bic：0xFF & ~0x0F = 240 ──
        ldaddr  x20, m_bic
        bl      puts
        movz    x10, #0x00FF
        mov     x11, #15
        bic     x12, x10, x11
        mov     x0, x12
        bl      printdec
        bl      pnl

        # ── T10 mvn：~0 = -1 ──
        ldaddr  x20, m_mvn
        bl      puts
        mov     x10, #0
        mvn     x12, x10
        mov     x0, x12
        bl      printdec
        bl      pnl

        # ── T11/T12 csel：max(7,3)=7、min(7,3)=3 ──
        ldaddr  x20, m_csel
        bl      puts
        mov     x10, #7
        mov     x11, #3
        cmp     x10, x11
        csel    x12, x10, x11, gt         # 7>3 为真 → 取 7
        mov     x0, x12
        bl      printdec
        bl      pnl
        # 第二次 csel 前必须**重建标志**：printdec 内部用过 cmp/subs，
        # 标志在调用后并不保持 —— csel 读的是当前标志，不是"上次 cmp 的"。
        cmp     x10, x11
        csel    x12, x11, x10, gt         # 真 → 取 3
        ldaddr  x20, m_csel2
        bl      puts
        mov     x0, x12
        bl      printdec
        bl      pnl

        # ── T13 cbz：循环 10 次累加 = 55，计数用 subs 带标志 ──
        ldaddr  x20, m_cbz
        bl      puts
        mov     x10, #10
        mov     x11, #0
cbz_loop:
        add     x11, x11, x10
        subs    x10, x10, #1
        cbz     x10, cbz_done
        b       cbz_loop
cbz_done:
        mov     x0, x11
        bl      printdec
        bl      pnl

        # ── T14 cbnz：同样累加到 55，但计数用 **sub**（不设标志）──
        #   若 cbnz 被错编成依赖标志的 b.ne，这里的 sub 不会置位，
        #   循环会提前退出或走飞 —— 用 sub 是为了让这条差异暴露出来。
        ldaddr  x20, m_cbnz
        bl      puts
        mov     x10, #10
        mov     x11, #0
cbnz_loop:
        add     x11, x11, x10
        sub     x10, x10, #1
        cbnz    x10, cbnz_loop
        mov     x0, x11
        bl      printdec
        bl      pnl

        # ── T15 subs：循环 5 次累加 = 15 ──
        ldaddr  x20, m_subs
        bl      puts
        mov     x10, #5
        mov     x11, #0
        mov     x13, #1
subs_loop:
        add     x11, x11, x10
        subs    x10, x10, x13      # 寄存器形式：与立即数形式不是同一条编码
        b.ne    subs_loop
        mov     x0, x11
        bl      printdec
        bl      pnl

        # ── T16 adds：0 + 0 必须置 Z ──
        #   先把 Z 清成 0（1 vs 0 不等），否则前一条 subs 留下的 Z=1
        #   会让 b.eq 无论 adds 对不对都成立 —— 判据就空转了。
        ldaddr  x20, m_adds
        bl      puts
        mov     x12, #1
        cmp     x12, #0
        mov     x10, #0
        adds    x11, x10, #0
        b.eq    adds_ok
        mov     x12, #0
        b       adds_end
adds_ok:
        mov     x12, #1
adds_end:
        mov     x0, x12
        bl      printdec
        bl      pnl

        # ── T17 strh/ldrh：半字 0x1234 = 4660 ──
        ldaddr  x20, m_half
        bl      puts
        ldaddr  x10, hbuf
        movz    x11, #0x1234
        strh    w11, [x10]
        ldrh    w12, [x10]
        mov     x0, x12
        bl      printdec
        bl      pnl

        ldaddr  x20, m_done
        bl      puts
halt:
        wfi
        b       halt

        .data
m_boot:     .asciz "MO-ARITH\n"
m_udiv:     .asciz "U="
m_rem:      .asciz "R="
m_sdiv:     .asciz "S="
m_sdiv2:    .asciz "S2="
m_lsr:      .asciz "L="
m_asr:      .asciz "A="
m_asr2:     .asciz "A2="
m_neg:      .asciz "N="
m_bic:      .asciz "B="
m_mvn:      .asciz "V="
m_csel:     .asciz "C="
m_csel2:    .asciz "C2="
m_cbz:      .asciz "Z="
m_cbnz:     .asciz "NZ="
m_subs:     .asciz "SU="
m_adds:     .asciz "AD="
m_half:     .asciz "H="
m_done:     .asciz "DONE\n"
hbuf:       .zero 8
            .zero 4096
stack_top:
