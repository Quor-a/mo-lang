    .include "consts.s"
##############################################################################
#  stmt.s -- 语句 / 块 / 函数 / 顶层
##############################################################################
    .section .data
    .globl frame_patch
frame_patch: .quad 0

    .text

##############################################################################
#  parse_program
##############################################################################
    .globl parse_program
parse_program:
    call predeclare
    call next_token
.Lt1:
    movq tok_kind(%rip), %rax
    testq %rax, %rax
    jz .Lt_done
    leaq S_var(%rip), %rsi
    call tok_is
    testq %rax, %rax
    jnz .Lt_var
    leaq S_fn(%rip), %rsi
    call tok_is
    testq %rax, %rax
    jnz .Lt_fn
    call syntax_error
.Lt_var:
    call parse_global
    jmp .Lt1
.Lt_fn:
    call parse_func
    jmp .Lt1
.Lt_done:
    ret

##############################################################################
#  parse_global :  var name : i64 = <整数|字符串> ;
##############################################################################
    .globl parse_global
parse_global:
    pushq %rbx
    subq $272, %rsp
    call next_token                  # 吃掉 'var'
    movq tok_kind(%rip), %rax
    cmpq $1, %rax
    je .Lg_ok
    call syntax_error
.Lg_ok:
    leaq tokbuf(%rip), %rsi
    leaq (%rsp), %rdi
    call memcpy_ex
    call next_token
    leaq S_colon(%rip), %rsi
    call expect
    leaq S_i64(%rip), %rsi
    call expect
    leaq S_eq(%rip), %rsi
    call expect
    # 分配数据槽
    # 🔴 必须对齐到 16，与 moc 的 data_align(16) 完全一致。
    #    不对齐的话 seed 与 moc 编译 compiler.mo 得到的数据段布局不同
    #    —— 自举直接不一致（"改编译期副作用要两边同步"再次应验）。
    #    对齐的原因见 compiler_part5.mo 里 data_align 的注释
    #    （pthread_mutex_t 里的 futex word 要求地址对齐）。
    movq data_len(%rip), %rbx
    addq $15, %rbx
    andq $-16, %rbx
    movq %rbx, data_len(%rip)
    movq %rbx, %rax
    addq $DATA_VADDR, %rax           # 绝对地址
    movq %rax, 256(%rsp)
    # 值
    movq tok_kind(%rip), %rax
    cmpq $2, %rax
    je .Lg_int
    cmpq $3, %rax
    je .Lg_str
    call syntax_error
.Lg_int:
    movq tok_ival(%rip), %rdi
    jmp .Lg_emit
.Lg_str:
    movq tok_ival(%rip), %rdi
.Lg_emit:
    call dquad
    call next_token
    leaq S_semi(%rip), %rsi
    call expect
    # sym_add(name, kind=2, addr, 0)
    leaq (%rsp), %rdi
    movq $2, %rsi
    movq 256(%rsp), %rdx
    xorq %rcx, %rcx
    call sym_add
    addq $272, %rsp
    popq %rbx
    ret

##############################################################################
#  parse_func
##############################################################################
    .globl parse_func
parse_func:
    pushq %rbx
    subq $560, %rsp
    #  (%rsp)[0..255]   函数名
    #  256(%rsp)        nsym_base
    #  264(%rsp)        nparams
    #  272(%rsp)        函数地址
    #  280(%rsp)        nsym_after_fn
    #  288(%rsp)[0..255] 参数名
    call next_token                  # 吃掉 'fn'
    movq tok_kind(%rip), %rax
    cmpq $1, %rax
    je .Lf_nok
    call syntax_error
.Lf_nok:
    leaq tokbuf(%rip), %rsi
    leaq (%rsp), %rdi
    call memcpy_ex
    call next_token
    leaq S_lp(%rip), %rsi
    call expect
    movq nsym(%rip), %rax
    movq %rax, 256(%rsp)
    movq $1, cur_depth(%rip)
    # 🔴 rbx 保存槽固定占 [rbp-8]（g_prologue 里 push rbx 在 sub rsp 之前）。
    #    局部变量必须从 [rbp-16] 起 —— 沿用 -8 会把第一个局部变量写进
    #    rbx 槽（与 moc 必须一致，否则自举挂）。
    movq $-16, cur_fn_off(%rip)
    movq $0, 264(%rsp)
    # --- 先登记函数符号（允许递归/前向调用） ---
    movq code_len(%rip), %rax
    addq $CODE_OFF, %rax
    addq $CODE_VADDR, %rax
    movq %rax, 272(%rsp)
    leaq (%rsp), %rdi
    call sym_lookup_func
    cmpq $-1, %rax
    je .Lf_new
    # 已预声明：更新地址
    leaq sym_addr(%rip), %r9
    movq 272(%rsp), %r10
    movq %r10, (%r9,%rax,8)
    jmp .Lf_after
.Lf_new:
    leaq (%rsp), %rdi
    movq $0, %rsi
    movq 272(%rsp), %rdx
    movq $0, %rcx
    call sym_add
.Lf_after:
    movq nsym(%rip), %rax
    movq %rax, 280(%rsp)
    # --- 参数 ---
    movq $16, %rbx
.Lf_p1:
    leaq S_rp(%rip), %rsi
    call tok_is
    testq %rax, %rax
    jnz .Lf_pdone
    movq tok_kind(%rip), %rax
    cmpq $1, %rax
    je .Lf_pok
    call syntax_error
.Lf_pok:
    leaq tokbuf(%rip), %rsi
    leaq 288(%rsp), %rdi
    call memcpy_ex
    call next_token
    leaq S_colon(%rip), %rsi
    call expect
    leaq S_i64(%rip), %rsi
    call expect
    leaq 288(%rsp), %rdi
    movq $1, %rsi
    movq cur_fn_off(%rip), %rdx
    movq %rdx, %rax
    subq $8, %rax
    movq %rax, cur_fn_off(%rip)
    xorq %rcx, %rcx
    call sym_add
    movq 264(%rsp), %rax
    incq %rax
    movq %rax, 264(%rsp)
    leaq S_comma(%rip), %rsi
    call accept
    testq %rax, %rax
    jnz .Lf_p1
.Lf_pdone:
    leaq S_rp(%rip), %rsi
    call expect
    leaq S_arrow(%rip), %rsi
    call expect
    leaq S_i64(%rip), %rsi
    call expect
    # 回填 npar
    movq nsym(%rip), %rax
    decq %rax                        # 参数区里没有函数符号，需定位函数符号
    # 函数符号索引
    leaq (%rsp), %rdi
    call sym_lookup_func
    movq %rax, 288+256(%rsp)
    leaq sym_npar(%rip), %r9
    movq 264(%rsp), %r10
    movq %r10, (%r9,%rax,8)
    # --- prologue ---
    movb $0x55, %dil
    call emit1
    movb $0x48, %dil
    call emit1
    movb $0x89, %dil
    call emit1
    movb $0xe5, %dil
    call emit1
    movb $0x53, %dil                 # push rbx（callee-saved，栈顶缓存会改它）
    call emit1
    movb $0x48, %dil
    call emit1
    movb $0x81, %dil
    call emit1
    movb $0xec, %dil
    call emit1
    movq code_len(%rip), %rax
    movq %rax, frame_patch(%rip)
    xorq %rdi, %rdi
    call emit4
    # --- 把寄存器传入的参数写入各自栈槽 ---
    pushq %r14
    movq $0, %r14
.Lf_save:
    movq 272(%rsp), %rax
    movq %rax, %r15                # 参数总数，供 emit_store_arg 计算栈上偏移
    cmpq %r14, %rax
    jbe .Lf_save_done
    movq %r14, %rdi
    imulq $8, %rdi
    addq $16, %rdi              # 🔴 参数槽从 [rbp-16] 起：[rbp-8] 是 rbx 保存槽
    negq %rdi
    movq %r14, %rsi
    movq %r15, %rdx
    call emit_store_arg
    incq %r14
    jmp .Lf_save
.Lf_save_done:
    popq %r14
    # --- body ---
    movq $2, %rdi
    call parse_block
    # --- 回填帧大小 ---
    movq cur_fn_off(%rip), %rax
    negq %rax
    # 🔴 序言多了一个 push rbx：进入函数体时 rsp = rbp - 8 - frame，
    #    要满足 call 时 rsp%16==0，frame 必须 ≡ 8 (mod 16)。
    #    仍按 ≡ 0 对齐会整体偏 8 字节（与 moc 不一致，自举直接挂）。
    addq $7, %rax
    andq $-16, %rax
    addq $8, %rax
    leaq codebuf(%rip), %r8
    movq frame_patch(%rip), %r9
    movl %eax, (%r8,%r9)
    # --- epilogue ---
    call g_epilogue
    # --- 恢复符号表 ---
    movq 280(%rsp), %rax
    movq %rax, nsym(%rip)
    movq $0, cur_depth(%rip)
    addq $560, %rsp
    popq %rbx
    ret

##############################################################################
#  parse_block(rdi=depth)
##############################################################################
    .globl parse_block
parse_block:
    pushq %rbx
    pushq %r12
    movq %rdi, %rbx
    movq cur_depth(%rip), %r12
    movq %rbx, cur_depth(%rip)
    leaq S_lb(%rip), %rsi
    call expect
.Lb1:
    leaq S_rb(%rip), %rsi
    call tok_is
    testq %rax, %rax
    jnz .Lb_done
    call parse_stmt
    jmp .Lb1
.Lb_done:
    call next_token
    movq %rbx, %rdi
    call sym_pop_scope
    movq %r12, cur_depth(%rip)
    popq %r12
    popq %rbx
    ret

##############################################################################
#  parse_stmt
##############################################################################
    .globl parse_stmt
    .globl compound_op
compound_op:
    leaq S_addeq(%rip), %rsi
    call tok_is
    testq %rax, %rax
    jnz .Lco1
    leaq S_subeq(%rip), %rsi
    call tok_is
    testq %rax, %rax
    jnz .Lco2
    leaq S_muleq(%rip), %rsi
    call tok_is
    testq %rax, %rax
    jnz .Lco3
    leaq S_diveq(%rip), %rsi
    call tok_is
    testq %rax, %rax
    jnz .Lco4
    leaq S_modeq(%rip), %rsi
    call tok_is
    testq %rax, %rax
    jnz .Lco5
    leaq S_andeq(%rip), %rsi
    call tok_is
    testq %rax, %rax
    jnz .Lco6
    leaq S_oreq(%rip), %rsi
    call tok_is
    testq %rax, %rax
    jnz .Lco7
    leaq S_xoreq(%rip), %rsi
    call tok_is
    testq %rax, %rax
    jnz .Lco8
    xorq %rax, %rax
    ret
.Lco1:
    movq $1, %rax
    ret
.Lco2:
    movq $2, %rax
    ret
.Lco3:
    movq $3, %rax
    ret
.Lco4:
    movq $4, %rax
    ret
.Lco5:
    movq $5, %rax
    ret
.Lco6:
    movq $6, %rax
    ret
.Lco7:
    movq $7, %rax
    ret
.Lco8:
    movq $8, %rax
    ret

parse_stmt:
    subq $288, %rsp
    #  (%rsp)[0..255]  名字/label 槽
    #  256(%rsp) label A / 264(%rsp) label B / 272(%rsp) sym / 280(%rsp) pos
    leaq S_break(%rip), %rsi
    call accept
    testq %rax, %rax
    jnz .Ls_break
    leaq S_cont(%rip), %rsi
    call accept
    testq %rax, %rax
    jnz .Ls_cont
    leaq S_let(%rip), %rsi
    call tok_is
    testq %rax, %rax
    jnz .Ls_let
    leaq S_if(%rip), %rsi
    call tok_is
    testq %rax, %rax
    jnz .Ls_if
    leaq S_while(%rip), %rsi
    call tok_is
    testq %rax, %rax
    jnz .Ls_while
    leaq S_return(%rip), %rsi
    call tok_is
    testq %rax, %rax
    jnz .Ls_return
    movq tok_kind(%rip), %rax
    cmpq $1, %rax
    jne .Ls_exprstmt
    leaq tokbuf(%rip), %rsi
    leaq (%rsp), %rdi
    call memcpy_ex
    movq tok_pos(%rip), %rax
    movq %rax, 280(%rsp)
    call next_token
    leaq S_eq(%rip), %rsi
    call tok_is
    testq %rax, %rax
    jnz .Ls_assign
    call compound_op
    testq %rax, %rax
    jnz .Ls_compound
    movq 280(%rsp), %rdi
    call set_pos
    jmp .Ls_exprstmt
.Ls_done:
    addq $288, %rsp
    ret

    # ---- let ----
.Ls_let:
    call next_token
    movq tok_kind(%rip), %rax
    cmpq $1, %rax
    je .Lsl_ok
    call syntax_error
.Lsl_ok:
    leaq tokbuf(%rip), %rsi
    leaq (%rsp), %rdi
    call memcpy_ex
    call next_token
    leaq S_colon(%rip), %rsi
    call expect
    leaq S_i64(%rip), %rsi
    call expect
    leaq S_eq(%rip), %rsi
    call expect
    call parse_expr
    leaq S_semi(%rip), %rsi
    call expect
    # 分配局部槽
    movq cur_fn_off(%rip), %rdx
    movq %rdx, %rax
    subq $8, %rax
    movq %rax, cur_fn_off(%rip)
    leaq (%rsp), %rdi
    movq $1, %rsi
    xorq %rcx, %rcx
    call sym_add
    movq %rdx, %rdi
    call g_store_local
    jmp .Ls_done

    # ---- 赋值 ----
.Ls_assign:
    call next_token
    call parse_expr
    leaq S_semi(%rip), %rsi
    call expect
    leaq (%rsp), %rdi
    call sym_lookup
    cmpq $-1, %rax
    je .Ls_undef
    movq %rax, 272(%rsp)
    movq %rax, %rdi
    call sym_kind_of
    cmpq $1, %rax
    je .Lsa_local
    movq 272(%rsp), %rdi
    call sym_addr_of
    movq %rax, %rdi
    call g_store_global
    jmp .Ls_done
.Lsa_local:
    movq 272(%rsp), %rdi
    call sym_addr_of
    movq %rax, %rdi
    call g_store_local
    jmp .Ls_done
    # ---- 复合赋值 x OP= e ----
    # 序列必须与 moc 的复合赋值分支**逐字节一致**：
    #   load → push → parse_expr → expect(';') → 读 last/lastv → pop_rcx → op → store
    #
    # 🔴 读 last/lastv 必须在 g_pop_rcx **之前**：g_pop_rcx 会清掉 last。
.Ls_compound:
    movq %rax, 256(%rsp)             # op（复用 label A 槽）
    call next_token
    leaq (%rsp), %rdi
    call sym_lookup
    cmpq $-1, %rax
    je .Ls_undef
    movq %rax, 272(%rsp)
    movq %rax, %rdi
    call sym_kind_of
    cmpq $1, %rax
    je .Lsc_local
    movq 272(%rsp), %rdi
    call sym_addr_of
    movq %rax, %rdi
    call g_load_global
    jmp .Lsc_go
.Lsc_local:
    movq 272(%rsp), %rdi
    call sym_addr_of
    movq %rax, %rdi
    call g_load_local
.Lsc_go:
    call g_push_rax
    call parse_expr
    leaq S_semi(%rip), %rsi
    call expect
    movq $-1, pow2k(%rip)
    movq $0, pow2d(%rip)
    movq 256(%rsp), %rax
    cmpq $4, %rax
    je .Lsc_div
    cmpq $5, %rax
    jne .Lsc_pop
.Lsc_div:
    movq last(%rip), %rax
    cmpq $1, %rax
    jne .Lsc_pop
    movq lastv(%rip), %rax
    movq %rax, pow2d(%rip)
    movq %rax, %rdi
    call is_pow2
    movq %rax, pow2k(%rip)
.Lsc_pop:
    call g_pop_rcx
    movq 256(%rsp), %rax
    cmpq $1, %rax
    je .Lsc_add
    cmpq $2, %rax
    je .Lsc_sub
    cmpq $3, %rax
    je .Lsc_mul
    cmpq $6, %rax
    je .Lsc_and
    cmpq $7, %rax
    je .Lsc_or
    cmpq $8, %rax
    je .Lsc_xor
    # 4=/ 5=%
    cmpq $4, %rax
    je .Lsc_d0
    movq pow2k(%rip), %rsi
    cmpq $0, %rsi
    jl .Lsc_magic
    movq $1, %rdi
    call g_div_pow2
    jmp .Lsc_st
.Lsc_d0:
    movq pow2k(%rip), %rsi
    cmpq $0, %rsi
    jl .Lsc_magic
    movq $0, %rdi
    call g_div_pow2
    jmp .Lsc_st
.Lsc_magic:
    movq pow2d(%rip), %rdi
    call magic_ok
    testq %rax, %rax
    jz .Lsc_plain
    movq pow2d(%rip), %rsi
    movq 256(%rsp), %rax
    cmpq $4, %rax
    je .Lsc_m0
    movq $1, %rdi
    call g_div_magic
    jmp .Lsc_st
.Lsc_m0:
    movq $0, %rdi
    call g_div_magic
    jmp .Lsc_st
.Lsc_plain:
    movq 256(%rsp), %rax
    cmpq $4, %rax
    je .Lsc_p0
    call g_mod
    jmp .Lsc_st
.Lsc_p0:
    call g_div
    jmp .Lsc_st
.Lsc_add:
    call g_add_rax_rcx
    jmp .Lsc_st
.Lsc_sub:
    call g_sub
    jmp .Lsc_st
.Lsc_mul:
    call g_imul
    jmp .Lsc_st
.Lsc_and:
    call g_and
    jmp .Lsc_st
.Lsc_or:
    call g_or
    jmp .Lsc_st
.Lsc_xor:
    call g_xor
    jmp .Lsc_st
.Lsc_st:
    movq 272(%rsp), %rdi
    call sym_kind_of
    cmpq $1, %rax
    je .Lsc_stl
    movq 272(%rsp), %rdi
    call sym_addr_of
    movq %rax, %rdi
    call g_store_global
    jmp .Ls_done
.Lsc_stl:
    movq 272(%rsp), %rdi
    call sym_addr_of
    movq %rax, %rdi
    call g_store_local
    jmp .Ls_done

.Ls_undef:
    leaq (%rsp), %rdi
    call err_undef

    # ---- if ----
.Ls_if:
    call next_token
    call new_label
    movq %rax, 264(%rsp)          # Lend —— 整条 if/else if 链共用的出口
    movq cur_depth(%rip), %rax
    incq %rax
    movq %rax, 272(%rsp)          # d
.Lif_iter:
    call parse_expr
    call g_cmp_rax_0
    call new_label
    movq %rax, 256(%rsp)          # Lelse —— 本轮的「下一分支」
    movq $0x84, %rdi
    movq 256(%rsp), %rsi
    call emit_jcc
    movq 272(%rsp), %rdi
    call parse_block
    movq 264(%rsp), %rdi
    call emit_jmp
    movq 256(%rsp), %rdi
    call place_label
    leaq S_else(%rip), %rsi
    call tok_is
    testq %rax, %rax
    jz .Lif_tail
    call next_token
    leaq S_if(%rip), %rsi
    call tok_is
    testq %rax, %rax
    jz .Lif_els
    call next_token
    jmp .Lif_iter
.Lif_els:
    movq 272(%rsp), %rdi
    call parse_block
.Lif_tail:
    movq 264(%rsp), %rdi
    call place_label
    jmp .Ls_done

    # ---- break ----
.Ls_break:
    leaq S_semi(%rip), %rsi
    call expect
    call loop_brk
    cmpq $-1, %rax
    je .Ls_brk_err
    movq %rax, %rdi
    call emit_jmp
    jmp .Ls_done
.Ls_brk_err:
    leaq E_BRK(%rip), %rdi
    movq $22, %rsi
    call die

    # ---- continue ----
.Ls_cont:
    leaq S_semi(%rip), %rsi
    call expect
    call loop_cnt
    cmpq $-1, %rax
    je .Ls_cnt_err
    movq %rax, %rdi
    call emit_jmp
    jmp .Ls_done
.Ls_cnt_err:
    leaq E_CNT(%rip), %rdi
    movq $25, %rsi
    call die

.Ls_while:
    call next_token
    call new_label
    movq %rax, 256(%rsp)          # Lstart
    call new_label
    movq %rax, 264(%rsp)          # Lend
    movq 256(%rsp), %rdi
    movq 264(%rsp), %rsi
    call loop_push
    movq 256(%rsp), %rdi
    call place_label
    call parse_expr
    call g_cmp_rax_0
    movq $0x84, %rdi
    movq 264(%rsp), %rsi
    call emit_jcc
    movq cur_depth(%rip), %rax
    incq %rax
    movq %rax, %rdi
    call parse_block
    movq 256(%rsp), %rdi
    call emit_jmp
    movq 264(%rsp), %rdi
    call place_label
    call loop_pop
    jmp .Ls_done

    # ---- return ----
.Ls_return:
    call next_token
    leaq S_semi(%rip), %rsi
    call tok_is
    testq %rax, %rax
    jnz .Lsr_void
    call parse_expr
.Lsr_void:
    leaq S_semi(%rip), %rsi
    call expect
    call g_epilogue
    jmp .Ls_done

    # ---- 表达式语句 ----
.Ls_exprstmt:
    call parse_expr
    leaq S_semi(%rip), %rsi
    call expect
    jmp .Ls_done

##############################################################################
#  predeclare : 扫描源码，把所有顶层 fn 名登记为函数符号（addr=0，稍后填真实地址）
##############################################################################
    .globl predeclare
predeclare:
    pushq %rbx
    subq $288, %rsp
    movq $0, %rbx                  # pos
.Lpd0:
    movq srclen(%rip), %rax
    cmpq %rax, %rbx
    jae .Lpd_done
    leaq srcbuf(%rip), %r10
    movb (%r10,%rbx), %al
    cmpb $32, %al
    je .Lpd_ws
    cmpb $9, %al
    je .Lpd_ws
    cmpb $10, %al
    je .Lpd_ws
    cmpb $13, %al
    je .Lpd_ws
    cmpb $35, %al
    je .Lpd_comment
    jmp .Lpd_chk
.Lpd_ws:
    incq %rbx
    jmp .Lpd0
.Lpd_comment:
    incq %rbx
.Lpd_c1:
    leaq srcbuf(%rip), %r10
    movq srclen(%rip), %rax
    cmpq %rax, %rbx
    jae .Lpd_done
    movb (%r10,%rbx), %al
    incq %rbx
    cmpb $10, %al
    jne .Lpd_c1
    jmp .Lpd0
.Lpd_chk:
    # 检查是否 "fn "
    movb (%r10,%rbx), %al
    cmpb $102, %al                 # 'f'
    jne .Lpd_skip
    movb 1(%r10,%rbx), %al
    cmpb $110, %al                 # 'n'
    jne .Lpd_skip
    movb 2(%r10,%rbx), %al
    cmpb $32, %al
    jne .Lpd_skip
    # 读标识符
    addq $3, %rbx
    leaq (%rsp), %r11
    xorq %rcx, %rcx
.Lpd_id:
    leaq srcbuf(%rip), %r10
    movb (%r10,%rbx), %al
    movzbq %al, %rdi
    pushq %rcx
    call is_alnum
    popq %rcx
    testq %rax, %rax
    jz .Lpd_idend
    movb (%r10,%rbx), %al
    movb %al, (%r11,%rcx)
    incq %rbx
    incq %rcx
    jmp .Lpd_id
.Lpd_idend:
    movb $0, (%r11,%rcx)
    # 必须是 '(' 才是函数定义
    movb (%r10,%rbx), %al
    cmpb $40, %al
    jne .Lpd_skip
    leaq (%rsp), %rdi
    movq $0, %rsi
    xorq %rdx, %rdx
    xorq %rcx, %rcx
    call sym_add
.Lpd_skip:
    # 跳到下一行
.Lpd_sk1:
    leaq srcbuf(%rip), %r10
    movq srclen(%rip), %rax
    cmpq %rax, %rbx
    jae .Lpd_done
    movb (%r10,%rbx), %al
    incq %rbx
    cmpb $10, %al
    je .Lpd0
    jmp .Lpd_sk1
.Lpd_done:
    addq $288, %rsp
    popq %rbx
    ret
