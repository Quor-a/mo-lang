/* 墨语言内核入口：Multiboot1 头 + 栈 + 清 bss + 跳转 main */

#define MB_MAGIC        0x1BADB002
#define MB_FLAGS        0x00000003   /* 要求对齐 + 要求内存信息 */
#define MB_CHECKSUM     -(MB_MAGIC + MB_FLAGS)

.section .multiboot, "a"
.align 4
.long MB_MAGIC
.long MB_FLAGS
.long MB_CHECKSUM

.section .text
.global _start
.type _start, @function
_start:
    /* 关中断，建立 16KB 栈 */
    cli
    movl $stack_top, %esp
    andl $-16, %esp

    /* 清 .bss：不清的话全局变量初值不是 0 */
    movl $_sbss, %edi
    movl $_ebss, %ecx
    subl %edi, %ecx
    jz   .Lbss_done
    xorl %eax, %eax
    rep  stosb
.Lbss_done:

    /* 压入 Multiboot 信息指针并进入墨语言的 main */
    pushl %ebx      /* multiboot info struct */
    pushl %eax      /* magic */
    call  main
    addl  $8, %esp

    /* main 返回就停机 */
    cli
.Lhang:
    hlt
    jmp .Lhang

.section .bss
.align 16
stack_bottom:
    .skip 16384
stack_top:
