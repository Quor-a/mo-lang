# unused.s —— 归档成员 3：**没有任何人引用** fnz
#   它存在的唯一意义是当"按需抽取"的对照：
#     · 做了按需 → 它不进产物 → 产物里搜不到 "ZZ-UNUSED"
#     · 不做按需 → 它进产物   → 产物里能搜到
#   只验"能跑通"分不出这两种情况，因为两种都能跑通。
        .text
        .globl fnz
fnz:
        adrp    x0, z_msg
        addlo   x0, x0, z_msg
        bl      puts
        ret

        .data
z_msg:  .asciz "ZZ-UNUSED\n"
