;------------------------------------------------------------------------------
;				OS LOADER
; Loaded at 0x7E00 to 0x9FC00. (0x9FC00 - 0x7E00 = 0x97E00)
;
; Assumes:
; 	- Stackpointer set
;	- Loaded at 0x7E00
;
;
;------------------------------------------------------------------------------

[BITS 16]
[ORG 0x7E00]

; DIKOS signature "DIOSDIOS" (4 bytes)
dikos_signature dd 0xD105D105

; Offset 4 bytes
start:
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

	mov si, msg_entry
	call print_string_16

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
	mov si, msg_success
	call print_string_16

	jmp $

a20_disabled:
	mov si, msg_a20_disabled
	call print_string_16
	jmp halt

; Error printing routines that jump to halt
no_cpuid:
	mov si, msg_no_cpuid
	call print_string_16
	jmp halt


no_long_mode:
	mov si, msg_no_long_mode
	call print_string_16
	jmp halt

; Halts the CPU
halt:
	mov esi, msg_halt
	call print_string_16
	jmp $


msg_entry db 'OS_Loader started', 0x0D, 0x0A, 0x00
msg_no_long_mode db 'Long mode not supported', 0x0D,0x0A, 0x00
msg_no_cpuid db 'No CPUID',0x0D, 0x0A, 0x00
msg_a20_disabled db 'A20 line could not be enabled',0x0D, 0x0A, 0x00
msg_halt	db 'CPU HALT!', 0x0A,0x0D, 0x00
msg_success db 'Standing by...',0x0D, 0x0A, 0x00

; 16-bit function to print a sting to the screen
print_string_16:                        ; Output string in SI to screen
        pusha
        mov ah, 0x0E                    ; http://www.ctyme.com/intr/rb-0106.htm
print_string_16_repeat:
        lodsb                           ; Get char from string
        cmp al, 0
        je print_string_16_done         ; If char is zero, end of string
        int 0x10                        ; Otherwise, print it
        jmp print_string_16_repeat
print_string_16_done:
        popa
        ret

; print_number_16
;
; Prints a hex value
;
; input: ax 	= number
hex_prefix 	db '0x' 		; Prefix for the hex_str
hex_str 	db '0000', 0x0D, 0x0A, 0x00 ; Buffer for our hex value
hex   		db '0123456789ABCDEF'
reg16 		dw 0x0000
print_number_16:
	mov di, hex_str
	mov ax, [reg16]
	mov si, hex
	mov cx, 4   ;four places
hexloop:
	rol ax, 4   ;leftmost will
	mov bx, ax   ; become
	and bx, 0x0f   ; rightmost
	mov bl, [si + bx];index into hexstr
	mov [di], bl
	inc di
	dec cx
	jnz hexloop

	mov si, hex_prefix
	call print_string_16
	ret


%include "a20_line.asm"



; Pad to 8190 bytes (leave 2 bytes for halts, which can also be used as signature)
times 0x1FFE-($-$$) db 0x90
hlt
hlt
