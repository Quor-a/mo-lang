# buf.s —— 第二个 bss 使用者：12288 字节的大缓冲区
#   填充 12288 字节是判据的一部分，不是随手写的数字：
#     · bss 地址正确 → 写在 .data 之后，字符串完好
#     · bss 地址错成 .data 起点 → 12288 字节足以覆盖全部 .data
#       （含 4096 填充 + 全部字符串），DATA OK 那行必然消失
#   若只填 256 字节，恰好只覆盖 .zero 4096 的填充区，字符串侥幸活下来，
#   缺陷就测不出来（样本充分 ≠ 覆盖充分）。
        .text
        .globl bf_probe
        .globl bf_fill
        .globl bf_first
bf_probe:
        adrp    x1, buf
        addlo   x1, x1, buf
        ldrb    w0, [x1]
        ret
bf_first:
        adrp    x1, buf
        addlo   x1, x1, buf
        ldrb    w0, [x1]
        ret
bf_fill:
        adrp    x1, buf
        addlo   x1, x1, buf
        mov     w3, #165
        mov     x4, #0
        mov     x9, #12288
fill_loop:
        strb    w3, [x1]
        add     x1, x1, #1
        add     x4, x4, #1
        cmp     x4, x9
        b.ne    fill_loop
        ret

        .bss
        .align 8
buf:    .zero 12288
