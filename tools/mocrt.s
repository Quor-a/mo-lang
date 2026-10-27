# mocrt.s —— molink -nostdlib 时提供的最小运行时
#
# 编译器在 -c 模式下用 libc 的 exit() 收尾（这样 stdio 缓冲区才会被 flush）。
# 不链接 libc 时没有 exit，这里补一个只做 exit_group 系统调用的版本。
    .text
    .globl exit
exit:
    mov $60, %rax          # rdi 已是退出码
    syscall
