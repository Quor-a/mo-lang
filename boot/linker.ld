/* 墨语言内核链接脚本 —— 32 位 Multiboot（GRUB / QEMU -kernel 可直接加载） */
ENTRY(_start)
SECTIONS
{
    . = 0x100000;                 /* 1MB，Multiboot 的常规加载地址 */

    .multiboot ALIGN(4) : { *(.multiboot) }
    .text ALIGN(4) : { *(.text*) }
    .rodata ALIGN(4) : { *(.rodata*) }
    .data ALIGN(4) : { *(.data*) }
    .bss  ALIGN(4) :
    {
        _sbss = .;
        *(COMMON)
        *(.bss*)
        _ebss = .;
    }
}
