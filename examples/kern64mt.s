.text
.globl _start
# 抢占式多任务内核：定时器中断 → 保存现场 → 切换任务 → eret
# 向量表必须放在 VBAR 指向处；IRQ from current EL with SPx = VBAR + 0x280
_start:
	ldaddr	x0, vectors
	msr	vbar_el1, x0
	ldaddr	x0, stack_a
	add	x0, x0, #512
	sub	x0, x0, #256
	ldaddr	x1, task_a
	str	x1, [x0, #248]
	str	xzr, [x0, #240]
	ldaddr	x1, spslot
	str	x0, [x1, #0]
	ldaddr	x0, stack_b
	add	x0, x0, #512
	sub	x0, x0, #256
	ldaddr	x1, task_b
	str	x1, [x0, #248]
	str	xzr, [x0, #240]
	ldaddr	x1, spslot
	str	x0, [x1, #8]
	ldaddr	x1, nsw
	str	xzr, [x1]
	ldaddr	x1, cur
	str	xzr, [x1]
	mov	x0, #134217728
	mov	x1, #1
	str	x1, [x0]
	mov	x0, #134217984
	mov	x1, #1073741824
	str	x1, [x0]
	ldaddr	x1, spslot
	ldr	x0, [x1, #0]
	add	sp, x0, #0
	ldr	x0, [sp, #248]
	msr	elr_el1, x0
	eret
irq_entry:
	sub	sp, sp, #256
	stp	x0, x1, [sp, #0]
	stp	x2, x3, [sp, #16]
	stp	x4, x5, [sp, #32]
	stp	x6, x7, [sp, #48]
	stp	x8, x9, [sp, #64]
	stp	x10, x11, [sp, #80]
	stp	x12, x13, [sp, #96]
	stp	x14, x15, [sp, #112]
	stp	x16, x17, [sp, #128]
	stp	x18, x19, [sp, #144]
	stp	x20, x21, [sp, #160]
	stp	x22, x23, [sp, #176]
	stp	x24, x25, [sp, #192]
	stp	x26, x27, [sp, #208]
	stp	x28, x29, [sp, #224]
	str	x30, [sp, #240]
	mrs	x0, elr_el1
	str	x0, [sp, #248]
	mov	x0, #134283276
	ldr	x2, [x0]
	mov	x0, #134283280
	str	x2, [x0]
	ldaddr	x0, cur
	ldr	x1, [x0]
	add	x2, sp, #0
	ldaddr	x3, spslot
	mov	x4, #8
	mul	x4, x1, x4
	add	x3, x3, x4
	str	x2, [x3]
	ldaddr	x0, nsw
	ldr	x1, [x0]
	add	x1, x1, #1
	str	x1, [x0]
	ldaddr	x0, cur
	ldr	x1, [x0]
	mov	x2, #1
	sub	x2, x2, x1
	str	x2, [x0]
	ldaddr	x3, spslot
	mov	x4, #8
	mul	x4, x2, x4
	add	x3, x3, x4
	ldr	x0, [x3]
	add	sp, x0, #0
	ldr	x0, [sp, #248]
	msr	elr_el1, x0
	ldr	x30, [sp, #240]
	ldp	x28, x29, [sp, #224]
	ldp	x26, x27, [sp, #208]
	ldp	x24, x25, [sp, #192]
	ldp	x22, x23, [sp, #176]
	ldp	x20, x21, [sp, #160]
	ldp	x18, x19, [sp, #144]
	ldp	x16, x17, [sp, #128]
	ldp	x14, x15, [sp, #112]
	ldp	x12, x13, [sp, #96]
	ldp	x10, x11, [sp, #80]
	ldp	x8, x9, [sp, #64]
	ldp	x6, x7, [sp, #48]
	ldp	x4, x5, [sp, #32]
	ldp	x2, x3, [sp, #16]
	ldp	x0, x1, [sp, #0]
	add	sp, sp, #256
	eret
task_a:
	ldaddr	x10, nsw
	mov	x12, #150994944
tloop_a:
	ldr	x0, [x10]
	cmp	x0, #8
	b.ge	finish
	movz	x1, #65
	strb	w1, [x12]
	movz	x4, #0
dly_a:
	add	x4, x4, #1
	cmp	x4, #40
	b.lt	dly_a
	b	tloop_a
task_b:
	ldaddr	x10, nsw
	mov	x12, #150994944
tloop_b:
	ldr	x0, [x10]
	cmp	x0, #8
	b.ge	fhalt
	movz	x1, #66
	strb	w1, [x12]
	movz	x4, #0
dly_b:
	add	x4, x4, #1
	cmp	x4, #40
	b.lt	dly_b
	b	tloop_b
finish:
	mov	x12, #150994944
	ldaddr	x13, msg_ok
floop:
	ldrb	w1, [x13]
	cmp	x1, #0
	b.eq	fhalt
	strb	w1, [x12]
	add	x13, x13, #1
	b	floop
fhalt:
	wfi
	b	fhalt
.align 2048
vectors:
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
irqvec:
	b	irq_entry
.data
msg_ok:	.asciz "MT OK\n"
.align 8
nsw:	.zero 8
cur:	.zero 8
spslot:	.zero 16
stack_a:	.zero 512
stack_b:	.zero 512
