;------------------------------------------------------------------------------
;				OS LOADER
; Loaded at 0x7E00 to 0x9FC00. (0x9FC00 - 0x7E00 = 0x97E00)
;
; Assumes:
; 	- Stackpointer set
;	- Loaded at 0x7E00
;	- print_string 		= 	ax
;	- print_number_16	= 	bx
;
; TODO:
;	- Check CPUID availability
;
;------------------------------------------------------------------------------

[BITS 16]
[ORG 0x7E00]

start:
	; Save functions from bootloader
	mov WORD [print_string_16], ax
	mov WORD [print_number_16], bx

	; Print entry message
	mov esi, msg_entry
	call [print_string_16]

	; Reset all registers
	cli                             ; Disable all interrupts
	xor eax, eax
	xor ebx, ebx
	xor ecx, ecx
	xor edx, edx
	xor esi, esi
	xor edi, edi
	xor ebp, ebp
	mov ds, ax
	mov es, ax
	mov ss, ax
	mov fs, ax
	mov gs, ax
	cld		; Clear direction flag


	; Detect CPU compatibility (Check if Protected mode available)

	jmp $

	; Enter LONG MODE / PROTECTED MODE
	; SETUP GDT
	; SETUP IDT


msg_entry db 'os_loader:start', 0x0A, 0x00
print_string_16 dw 0x00
print_number_16 dw 0x00
