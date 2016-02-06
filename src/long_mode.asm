; Following AMD Manual, Vol 2, 14.6.1

[BITS 16]


%define PAGE_PRESENT 	0x01
%define PAGE_WRITE  	0x02

%define CODE_SEG	0x0008
%define DATA_SEG	0x0010


align 4	; Align to 4 bytes
IDT:
	.length	dw 0x00
	.base	dd 0x00

; es:edi    Should point to a valid page-aligned 16KiB buffer, for the PML4, PDPT, PD and a PT.
; ss:esp    Should point to memory that can be used as a small (1 uint32_t) stack
enter_long_mode:
	; Zero out 16KiB buffer by interating over ecx (4096) and writing to
	; es:edi
	push di
	mov ecx, 0x1000
	xor eax, eax
	cld
	rep stosd	; Repeatedly write eax (4 bytes) to [es:edi] (which is incremented)
	pop di

	; Create Page Map Level 4 Table (PML4)
	; es:edi points to PML4
	lea eax, [es:di + 0x1000]
	or eax, PAGE_PRESENT | PAGE_WRITE	; Or EAX with the flags
	mov [es:di], eax			; Store EAX as the first PML4E


	; Create the Page Directory Pointer Table (PDP)
	lea eax, [es:di + 0x2000]	; Load the address of PDP into EAX
	or eax, PAGE_PRESENT | PAGE_WRITE
	mov [es:di + 0x1000], eax	; Store EAX as the first PDPE


	; Build the Page Directory Table (PD)
	lea eax, [es:di + 0x3000]	; Load the address of PD into EAX
	or eax, PAGE_PRESENT | PAGE_WRITE
	mov [es:di + 0x2000], eax	; Store EAX as first PDE


	push di
	lea di, [di + 0x3000]		; Point di to the Page Table
	mov eax, PAGE_PRESENT | PAGE_WRITE


	; Build the Page Table (PT)
.loop_page_table:
	; Iterate over 2MiB and set the PAGE_PRESENT and PAGE_WRITE flags
	mov [es:di], eax
	add eax, 0x1000
	add di, 0x08
	cmp eax, 0x200000
	jb .loop_page_table


	pop di				; Restore DI

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


