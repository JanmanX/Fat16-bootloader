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
;
;------------------------------------------------------------------------------

[BITS 16]
[ORG 0x7E00]

; DIKOS signature "DIOSDIOS" (4 bytes)
dikos_signature dd 0xD105D105

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
;	mov fs, ax
;	mov gs, ax
	cld		; Clear direction flag


	; Check CPUID availability
	; If CPUID instruction is supported, the 'ID' bit (0x200000) in eflags
	; will be modifiable.
	pushfd			; Store EFLAGs
	pushfd			; Store EFLAGs again. (This will be modified)
	xor dword [esp], 0x00200000 ; Flip the ID flag
	popfd			; Load the modified EFLAGS
	pushfd			; Store it again for inspection
	pop eax
	xor eax, [esp]		; Compare to original EFLAGS
	popfd			; Restore original EFLAGs
	and eax, 0x00200000	; eax = 0 if ID bit cannot be changed, else non-zero
	jz no_cpuid


	; Check if Protected mode available
	mov eax, 0x80000000
	cpuid
	cmp eax, 0x80000000	; Check if functions above 0x80000000 exist
	jbe no_long_mode
	mov eax, 0x80000001	; Extended Processor Signature and Extended Feature Bits
	cpuid
	bt edx, 29		; Test if bit at offset 29 (long mode flag) is on
	jnc no_long_mode	; Exit if not supported


	; Enabling A20 line is recommended
	call enable_a20
	cmp ax, 0x00
	je a20_disabled



	; Enter LONG MODE (Directly from real mode. Experimental)

	; SETUP GDT
	; SETUP IDT

	; Success if this point reached
	mov esi, msg_success
	call [print_string_16]

	jmp $

a20_disabled:
	mov esi, msg_a20_disabled
	call [print_string_16]
	jmp halt

; Error printing routines that jump to halt
no_cpuid:
	mov esi, msg_no_cpuid
	call [print_string_16]
	jmp halt


no_long_mode:
	mov esi, msg_no_long_mode
	call [print_string_16]
	jmp halt

; Halts the CPU
halt:
	mov esi, msg_halt
	call [print_string_16]
	jmp $



msg_entry db 'os_loader: OS_Loader started', 0x0A, 0x00
msg_no_long_mode db 'os_loader: Long mode not supported', 0x0A, 0x00
msg_no_cpuid db 'os_loader: No CPUID', 0x0A, 0x00
msg_a20_disabled db 'os_loader: A20 line could not be enabled', 0x0A, 0x00
msg_halt	db 'os_loader: CPU HALT!', 0x0A, 0x00
msg_success db 'Standing by...', 0x0A, 0x00

print_string_16 dw 0x00
print_number_16 dw 0x00

%include "a20_line.asm"

; Pad to 8190 bytes (leave 2 bytes for halts, which can also be used as signature)
times 0x1FFE-($-$$) db 0x90
hlt
hlt
