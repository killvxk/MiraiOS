extern PAGE_SIZE
extern ackIRQ
extern initStackEnd
extern acquireSpinlock
extern releaseSpinlock

extern getCurrentThread
extern setCurrentThread
extern kthreadSwitch
extern kthreadFreeJoined
extern readyQueuePop

extern cprint

global kthreadInit:function
global jiffyIrq:function
global migrateMainStack:function
global kthreadStop:function

SECTION .text

;thread stack layout:
;init | resume | register
;-08	 XX		return to exit
;Saved by interrupt handler
;-10	+98		ss
;-18	+90		rsp
;-20	+88		rflags
;-28	+80		cs
;-30	+78		rip
;Mandatory saved registers
;-38	+70		rax
;-40	+68		rcx
;-48	+60		rdx
;-50	+58		rdi
;-58	+50		rsi
;-60	+48		r8
;-68	+40		r9
;-70	+38		r10
;-78	+30		r11
;Optionally saved registers (only on task switch)
;-80	+28		rbx
;-88	+20		rbp
;-90	+18		r12
;-98	+10		r13
;-A0	+08		r14
;-A8	rsp		r15

kthreadInit:
	push rbp
	mov rbp, rsp
	
	mov [rdi - 0x30], rsi	;Point rip to function start
	mov [rdi - 0x50], rdx	;Put arg in rdi
	mov rax, kthreadReturn
	mov [rdi - 0x08], rax	;Put return address on stack
	mov rax, rdi
	sub rax, 0x08
	mov [rdi - 0x18], rax	;Set rsp
	sub rax, 0xA0
	mov [rdi], rax			;Set stack pointer in threadInfo

	mov eax, 0x10			;data segment
	mov edx, 0x08			;code segment
	mov [rdi - 0x10], rax	;Set ss
	mov [rdi - 0x28], rdx	;Set cs

	mov rsp, rdi
	sub rsp, 0x18
	pushfq					;Set rflags

	leave
	ret

kthreadReturn:
	mov rdi, rax
kthreadExit:
	push rdi
	call getCurrentThread
	push rax
	lea rdi, [rax + 0x14]
	xchg bx, bx
	call acquireSpinlock

	xor rdi, rdi
	call setCurrentThread

	mov rax, [rsp]
	mov rdi, [rsp + 8]
	mov [rax + 8], rdi ;set return value
	mov [rax + 16], dword 0 ;set threadstate to FINISHED

	mov rdi, rax
	call kthreadFreeJoined

	mov rdi, [rsp]
	add rdi, 0x14
	call releaseSpinlock

	add rsp, 16
	jmp nextThread

jiffyIrq:
	;save mandatory registers
	sub rsp, 0x48
	mov [rsp + 0x40], rax
	mov [rsp + 0x38], rcx
	mov [rsp + 0x30], rdx
	mov [rsp + 0x28], rdi
	mov [rsp + 0x20], rsi
	mov [rsp + 0x18], r8
	mov [rsp + 0x10], r9
	mov [rsp + 0x08], r10
	mov [rsp], r11

	call getCurrentThread
	push rax
	call kthreadSwitch
	pop rdx

	test rdx, rdx
	jz .noSave ;skip if this cpu wasn't busy
		;task switch occured
		;save optional registers
		sub rsp, 0x30
		mov [rsp + 0x28], rbx
		mov [rsp + 0x20], rbp
		mov [rsp + 0x18], r12
		mov [rsp + 0x10], r13
		mov [rsp + 0x08], r14
		mov [rsp], r15
		;save rsp
		mov [rdx], rsp
	.noSave:
	;get new rsp
	mov rsp, [rax]
	;restore optional registers
	mov rbx, [rsp + 0x28]
	mov rbp, [rsp + 0x20]
	mov r12, [rsp + 0x18]
	mov r13, [rsp + 0x10]
	mov r14, [rsp + 0x08]
	mov r15, [rsp]
	add rsp, 0x30

	call ackIRQ
	;Restore mandatory registers
	mov rax, [rsp + 0x40]
	mov rcx, [rsp + 0x38]
	mov rdx, [rsp + 0x30]
	mov rdi, [rsp + 0x28]
	mov rsi, [rsp + 0x20]
	mov r8,  [rsp + 0x18]
	mov r9,  [rsp + 0x10]
	mov r10, [rsp + 0x08]
	mov r11, [rsp]
	add rsp, 0x48
	iretq

migrateMainStack:
	;rdi contains thread pointer
	mov r8, rdi

	std
	mov rsi, initStackEnd
	xor eax, eax
	;lea rcx, [initStackEnd - rsp]
	mov rcx, initStackEnd
	sub rcx, rsp
	add rcx, 8
	rep movsb
	cld

	;mov r8, rdi
	sub r8, initStackEnd
	add rsp, r8
	add rbp, r8
	ret

kthreadStop:
	;load return address in rdx
	pop rdx
	;setup stack for iret
	;push ss
	push 0x10
	;push stackpointer
	lea rax, [rsp + 8]
	push rax
	;push flags
	pushfq
	;push cs
	push 0x08
	;push return address
	push rdx

	
	;save opt regs only
	sub rsp, 0x78
	mov [rsp + 0x28], rbx
	mov [rsp + 0x20], rbp
	mov [rsp + 0x18], r12
	mov [rsp + 0x10], r13
	mov [rsp + 0x08], r14
	mov [rsp], r15

	call getCurrentThread

	test [rax + 0x14], dword 0x02 ;get IF on spinlock
	jz .noIRQ
		or [rsp + 0x88], dword (1 << 9) ;set IF on stack
	.noIRQ:

	mov [rax], rsp ;save rsp
	lea rdi, [rax + 0x14]
	call releaseSpinlock
nextThread:
	call readyQueuePop
	mov rdi, rax
	push rax
	call setCurrentThread
	pop rax

	;Halt if no task is available
	test rax, rax
	jnz .load
		hlt
		jmp nextThread
	.load:

	;xchg bx, bx
	mov rsp, [rax]
	;Restore registers
	mov rax, [rsp + 0x70]
	mov rcx, [rsp + 0x68]
	mov rdx, [rsp + 0x60]
	mov rdi, [rsp + 0x58]
	mov rsi, [rsp + 0x50]
	mov r8,  [rsp + 0x48]
	mov r9,  [rsp + 0x40]
	mov r10, [rsp + 0x38]
	mov r11, [rsp + 0x30]
	mov rbx, [rsp + 0x28]
	mov rbp, [rsp + 0x20]
	mov r12, [rsp + 0x18]
	mov r13, [rsp + 0x10]
	mov r14, [rsp + 0x08]
	mov r15, [rsp]
	add rsp, 0x78
	iretq

;return:
;	ret