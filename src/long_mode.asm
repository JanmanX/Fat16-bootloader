; Following AMD Manual, Vol 2, 14.6.1
%macro debug 1
	pusha
	mov ah, 0x0e    ; function number = 0Eh : Display Character
	mov al, %1     ; AL = code of character to display
	int 0x10        ; call INT 10h, BIOS video service
	popa
%endmacro
[map all long_mode.map]

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
; We will need:
; 1 PML4E * 2 PDPE * 512 PDE = 2 * 512 * 2MiB = 2GiB
%define NUM_PDP 2

; es:edi    Should point to a valid page-aligned 16KiB buffer, for the PML4, PDPT, PD and a PT.
; ss:esp    Should point to memory that can be used as a small (1 uint32_t) stack
enter_long_mode:
	; es:edi
	push edi
	mov ecx, 0x800000
	xor eax, eax
	cld
	rep stosd	; Repeatedly write eax (4 bytes) to [es:edi] (which is incremented)
	pop edi

	; Create Page Map Level 4 Table (PML4)
	; es:edi points to PML4
	lea eax, [es:di + 0x1000]         ; Put the address of the Page Directory Pointer Table in to EAX.
   	or eax, PAGE_PRESENT | PAGE_WRITE ; Or EAX with the flags - present flag, writable flag.
    	mov [es:di], eax                  ; Store the value of EAX as the first PML4E.

	debug '1'

	; Create the Page Directory Pointer Table (PDP)
	xor ebx, ebx
build_pdp:
	lea eax, [es:edi + ebx * 8 + 0x2000]
	or eax, PAGE_PRESENT | PAGE_WRITE
	lea ecx, [es:edi + ebx * 8 + 0x1000]
	mov [ecx], eax
	inc ebx
	cmp ebx, NUM_PDP
	debug '@'
	jb build_pdp

	debug '2'

	; Create the Page Directory Table
	push edi		; Save for later
	lea di, [edi + 0x2000]	; Point to PD table
	mov eax, PAGE_PRESENT | PAGE_WRITE | PAGE_SIZE
	xor ebx, ebx
build_pd:
	mov [es:edi], eax
	add eax, 0x200000	; Add 2 MiB
	add edi, 0x08		; Move to next entry
	cmp eax, NUM_PDP * 512 * 0x200000	; 2GiB = 0x80000000
	debug '#'
	jb build_pd

	pop edi

	debug '3'
debug_here:
	;jmp $

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

	call clear_screen
	mov rsi, msg_long_mode
	call print_string
	jmp $

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

