;------------------------------------------------------------------------------
;				OS LOADER
; Assumes:
;	- Loaded at 0x0000
;
; Sets SP to 0x7C00
;------------------------------------------------------------------------------

[BITS 16]
[ORG 0x8000]

; CONSTANTS
%define VIDEO_RAM 0xB8000		; Start of 80x25 video memory


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
	mov sp, 0x7C00	; Reset SP
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


	; Enable A20 line
	call enable_a20
	cmp ax, 0x00
	je a20_disabled

	; Enter long mode
	mov edi, 0xA000		; Place just after Stage2 (0x8000 + 0x2000)
	jmp enter_long_mode


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


; Variables used in REAL MODE
msg_entry 		db 'OS_Loader started', 0x0D, 0x0A, 0x00
msg_no_long_mode 	db 'Long mode not supported', 0x0D,0x0A, 0x00
msg_no_cpuid 		db 'No CPUID',0x0D, 0x0A, 0x00
msg_a20_disabled 	db 'A20 line could not be enabled',0x0D, 0x0A, 0x00
msg_halt		db 'CPU HALT!', 0x0A,0x0D, 0x00
msg_success 		db 'Standing by...',0x0D, 0x0A, 0x00


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


%include "src/a20_line.asm"
%include "src/long_mode.asm"

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;                                  64 BIT
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
[BITS 64]
long_mode:
	mov ax, DATA_SEG
	mov ds, ax
	mov es, ax
	mov fs, ax
	mov gs, ax
	mov ss, ax

	; Blank out the screen
	mov edi, VIDEO_RAM
	mov rcx, 25*80/4
	mov rax, 0x7F207F207F207F20	; 4 white on grey spaces
	rep stosq                         ; Clear the entire screen.

	; Display "Hello World!"
	mov edi, VIDEO_RAM
	mov esi, msg_long_mode
	mov ah, 0x7F
.loop:
	lodsb
	cmp al, 0x00
	je .loop_finished
	mov [edi], ax
	add edi, 0x02
	jmp .loop

.loop_finished
	jmp $


; Variables used in LONG MODE (64 bit)
msg_long_mode db 'Long mode entered', 0x00


; Pad to 8190 bytes
; Leave 4 bytes for signature
times 0x2000-($-$$) db 0x90
