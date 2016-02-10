; Following AMD Manual, Vol 2, 14.6.1
%macro debug 1
	pusha
	mov ah, 0x0e    ; function number = 0Eh : Display Character
	mov al, %1     ; AL = code of character to display
	int 0x10        ; call INT 10h, BIOS video service
	popa
%endmacro

[BITS 16]

%define PAGE_PRESENT 	0x01
%define PAGE_WRITE  	0x02
%define PAGE_SIZE	(1 << 7)


align 4	; Align to 4 bytes
IDT:
	.length	dw 0x00
	.base	dd 0x00

; Paging
;
; For simplicity, identity mapping will be used (virtual addr = physical addr)
; Also, 2MiB pages will be used. Page Size (PS) Bit in PDE must be set for 2MiB
; pages.
; Each PDPE maps 1 GiB: 1 * 512 * 2MiB = 1GiB.
; Therefore, for 64GiB, we need 64 PDP Entries
%define NUM_PDP 64
; Multiplication of 4096 is the same as shifting left 12 times.


; es:edi    Should point to a valid page-aligned 16KiB buffer, for the PML4, PDPT, PD and a PT.
; ss:esp    Should point to memory that can be used as a small (1 uint32_t) stack
enter_long_mode:
	push edi
	mov ecx, 0x800000
	xor eax, eax
	cld
	rep stosd	; Repeatedly write eax (4 bytes) to [es:edi] (which is incremented)
	pop edi

	; Create Page Map Level 4 Table (PML4)
	; es:di points to PML4
	lea eax, [es:di + 0x1000]         ; Put the address of the Page Directory Pointer Table in to EAX.
   	or eax, PAGE_PRESENT | PAGE_WRITE ; Or EAX with the flags - present flag, writable flag.
    	mov [es:di], eax                  ; Store the value of EAX as the first PML4E.
	debug '1'

	; Create the Page Directory Pointer Table (PDP)
	lea eax, [es:di + 0x2000]		; EAX points to first PDE
	or eax, PAGE_PRESENT | PAGE_WRITE
	mov [es:di + 0x1000], eax		; Store value of EAX as the first PDPE
	debug '2'

	; Create one entry in the Page Directory Table
	mov eax, PAGE_PRESENT | PAGE_WRITE | PAGE_SIZE
	mov [es:di + 0x2000], eax	; Map only one 2MiB Map. Rest will be done in Long Mode
	add eax, 0x00200000
	mov [es:di + 0x2008], eax
	debug '3'

	; Disable IRQs (Interrupt Requests from hardware)
	; http://wiki.osdev.org/8259_PIC#Disabling
	mov al, 0xFF
	out 0xA1, al			; Output AL to I/O port 0xA1
	out 0x21, al			; Output AL to I/O port 0x21

	; Load the Interrupt Descriptor Table (IDT)
	lidt [IDT]		; Causes an Non-Maskable Interrupt (NMI)

	; Enter long mode
	mov eax, 0xA0		; Set the PAE and PGE bits (5 and 7)
	mov cr4, eax

	mov edx, edi		; Point CR3 to PML4
	mov cr3, edx
	mov ecx, 0xC0000080	; Register Extended Feature Enable Register (EFER)
	rdmsr			; Read from Model Specific Register (MSR) specified
				; by ECX

	or eax, 0x00000100	; Set the LME bit
	wrmsr

 	mov ebx, cr0		; Activate long mode -
    	or ebx,0x80000001	; - by enabling paging and protection simultaneously.
    	mov cr0, ebx


	lgdt [GDT64.Pointer]	; Load Global Descriptor Table (GDT)

	jmp GDT64.KM_Code:long_mode


[BITS 64]
long_mode:
	mov ax, GDT64.KM_Data
	mov ds, ax
	mov es, ax
	mov fs, ax
	mov gs, ax
	mov ss, ax

        xor r8, r8
        xor r9, r9
        xor r10, r10
        xor r11, r11
        xor r12, r12
        xor r13, r13
        xor r14, r14
        xor r15, r15
	cld

	; Clear cr3 - to 0xA0000
	mov rdi, cr3			; Retrieve address of PML4
	add rdi, 0x1000			; Offset to PDP
	xor rcx, rcx			; Counter
build_pdp:
	; Calculate address of PDE
	mov rbx, rcx			; rbx must be used for lea
	shl rbx, 0x0c			; rbx = rcx * 0x1000
	lea rax, [rdi + 0x1000 + rbx]	; Address of PD Entry
	or rax, PAGE_PRESENT | PAGE_WRITE
	xchg rbx, rcx			; rcx cant be used in LEA
	lea rcx, [rdi + rbx * 8]	; Address of index to save to
	xchg rbx, rcx
	mov [rbx], rax			; Save entry to PDP
	inc rcx
	cmp rcx, NUM_PDP
	jb build_pdp


	; Create the rest of the Page Directory table
	mov rdi, cr3		; Get the address of PML4
	add rdi, 0x2000		; Offset to Page Directory Table.
	mov rax, PAGE_PRESENT | PAGE_WRITE | PAGE_SIZE
	xor rcx, rcx		; Counter
build_pd:
	stosq
	add rax, 0x200000	; Add 2 MiB offset
	inc rcx
	cmp rcx, NUM_PDP * 512	; If all entries have been written, exit
	jb build_pd




	call clear_screen
	mov rsi, msg_long_mode
	call print_string

debug_here:
	mov rax, 0x80000000
	mov rdi, rax
	mov [rdi], dword 0xCAFEBABE	; Store at 2GiB

	mov rsi, debugmsg
	call print_string


	add rdi, rax
	mov [rdi], dword 0xCAFEBABE	; Store at 4GiB

	mov rsi, debugmsg
	call print_string

	add rdi, rax
	mov [rdi], dword 0xCAFEBABE	; Store at 6GiB

	mov rsi, debugmsg
	call print_string

	add rdi, rax
	mov [rdi], dword 0xCAFEBABE	; Store at 8GiB

	mov rsi, debugmsg
	call print_string
	jmp $

	add rdi, rax
	mov [rdi], dword 0xCAFEBABE	; Store at 10GiB

	mov rsi, debugmsg
	call print_string



	jmp $
	push rdi
.loop:
	lodsb	; Load byte from [rsi] to al
	cmp al, 0x00
	je .loop_end
	mov byte [rdi], al
	inc rdi
	jmp .loop
.loop_end:
	pop rsi
	call print_string
	jmp $



debugmsg db 'THIS IS A LONG TEST DEBUG MESSAGE', 0x00
; Global Descriptor Table used for long mode
;
; LAYOUT:
; Limit			2 bytes
; Base 0:15		2 bytes
; Base 16:23		1 byte
; Access		1 byte
; Limit 16:19		4 bits
; Flags			4 bits
; Base 24:31		1 byte
;
; User Mode access byte
; +-------+-------+
; |  0xF  |  0xA  |
; +---------------+
; |1|1|1|1|1|0|1|0|
; ++-+-+-+-+-+-+-++
;  | | | | | | | |
;  | | | | | | | +-----> Accessed bit. Set it to zero.
;  | | | | | | +-------> Readable / Writeable bit. Readable bit for Code, Writeable for data sectors
;  | | | | | +---------> Direction Bit.
;  | | | | +-----------> Executable bit. 1 for Code, 0 for data
;  | | | +-------------> Must be 1.
;  | +-+---------------> Privilege, 2 bits. Containing ring level.
;  |
;  +-------------------> Preset bit. Must be 1 for all valid selectors.
GDT64:                           ; Global Descriptor Table (64-bit).
	.Null: equ $ - GDT64         ; The null descriptor.
	dw 0                         ; Limit (low).
	dw 0                         ; Base (low).
	db 0                         ; Base (middle)
	db 0                         ; Access.
	db 0                         ; Granularity.
	db 0                         ; Base (high).
	.KM_Code: equ $ - GDT64         ; The kernel mode code descriptor.
	dw 0                         ; Limit (low).
	dw 0                         ; Base (low).
	db 0                         ; Base (middle)
	db 10011010b                 ; Access (exec/read).
	db 00100000b                 ; Granularity.
	db 0                         ; Base (high).
	.KM_Data: equ $ - GDT64         ; The data descriptor.
	dw 0                         ; Limit (low).
	dw 0                         ; Base (low).
	db 0                         ; Base (middle)
	db 10010010b                 ; Access (read/write).
	db 00000000b                 ; Granularity.
	db 0                         ; Base (high).
	.UM_Code: equ $ - GDT64
	dw 0
	dw 0
	db 0
	db 0xFA
	db 0xCF
	db 0
	.UM_Data: equ $ - GDT64
	dw 0
	dw 0
	db 0
	db 0xF2
	db 0xCF
	db 0
	.Pointer:                    ; The GDT-pointer.
	dw $ - GDT64 - 1             ; Limit (length of GDT).
	dq GDT64                     ; Address of GDT64

