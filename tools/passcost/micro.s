    .text
    .globl mic_push, mic_reg
    .p2align 4
# A: 用 push/pop 传递中间值 —— 墨语言当前的做法
mic_push:
    movq $0, %rax
    movq $1, %rdx
    movq %rdi, %rcx
.Lp:
    push %rax
    pop  %r8
    add  %rdx, %r8
    push %r8
    pop  %rax
    add  %rdx, %rax
    dec  %rcx
    jne  .Lp
    ret
    .p2align 4
# B: 用寄存器传递 —— 寄存器分配后的做法（**指令条数与 A 相同**）
mic_reg:
    movq $0, %rax
    movq $1, %rdx
    movq %rdi, %rcx
.Lr:
    mov  %rax, %r8
    add  %rdx, %r8
    mov  %r8, %rax
    add  %rdx, %rax
    dec  %rcx
    jne  .Lr
    ret
