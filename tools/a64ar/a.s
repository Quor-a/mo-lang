# a.s —— 归档成员 1：定义 fna，并**引用 fnb**
#   fnb 定义在 b.s 里。这条引用是"传递抽取"的判据：
#   抽取 a.o 之后 fnb 才变成 UNDEF，抽取循环必须**再转一轮**把 b.o 拉进来。
#   只做一遍的实现会在 fnb 上报未定义 —— 症状看起来像"归档里缺文件"，
#   实际是循环少了一轮。
#
# ── fna 必须先保存 x30 ──────────────────────────────────────
#   AArch64 的 bl 会**覆盖** x30（链接寄存器）。fna 是**非叶子**函数
#   （自己还要 bl puts / bl fnb），如果不先存 x30：
#       bl puts  → x30 = "puts 之后"
#       bl fnb   → x30 = "fnb 之后"
#       fnb 内部 bl puts → x30 = "fnb 里 puts 之后"
#       fnb 的 ret → 跳回它自己的 ret 后面 → **死循环**
#   症状是"打印完 A、B 就停住，后面的 MO-AR / SYS OK 永远不出来"，
#   看起来像链接器把后半段代码弄丢了，其实是调用约定没遵守。
#   叶子函数（如 lib.s 的 puts）不需要，非叶子必须存。
        .text
        .globl fna
fna:
        sub     sp, sp, #16
        str     x30, [sp]
        adrp    x0, a_msg
        addlo   x0, x0, a_msg
        bl      puts
        bl      fnb
        ldr     x30, [sp]
        add     sp, sp, #16
        ret

        .data
a_msg:  .asciz "A\n"
