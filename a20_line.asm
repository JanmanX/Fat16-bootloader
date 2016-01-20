[BITS 16]
; Function: check_a20
;
; Purpose: Tests if A20 line is disabled
;
; Returns: 0 in ax if the a20 line is disabled (memory wraps around)
;          1 in ax if the a20 line is enabled (memory does not wrap around);
;
; This is done by testing if memory wraps around. The 2 bytes: 0xAA55
; are located at: 0x7C00 + (0x0200 - 0x0002) = 0x7DFE
; If A20 is enabled, the bytes at 1MiB above that should be the same:
; 	- 1MiB above 0x7DFE = FFFF:7E0E
check_a20:
	pushf
	push ds
 	push es
	push di
	push si
	cli

	xor ax, ax		; AX = 0
	mov es, ax		; ES = 0
	not ax			; AX = 0xFFFF
	mov ds, ax		; DS = 0xFFFF

	mov di, 0x7DFE		; Offset of our "0xAA55" boot signature
	mov si, 0x7E0E		; Offset of address of boot signature at 1 MiB
				; higher address (FFFF:7E0E)


	mov al, byte [es:di]	; Load the boot signature
	push ax			; Store on stack

	mov al, byte [ds:si]	; Load the offset boot signature
	push ax

	; Load completely opposite values into the memory locations
	mov byte [es:di], 0x00
	mov byte [ds:si], 0xFF	; If A20 disabled, this will wrap and overwrite
				; the '0x00'


	; DEBUG
	; Reset ds segment to correctly call the function
	xor ax, ax
	mov ds, ax
	mov al, byte [es:di]
	call [print_number_16]
	; Reset the ds
	xor ax, ax
	not ax
	mov ds, ax
	; END DEBUG

	; Check if the original value has been changed due to the wrap-around
	cmp byte [es:di], 0xFF	; Set ZF

	; Reload the original values
	pop ax
	mov byte [ds:si], al
	pop ax
	mov byte [ds:si], al

	mov ax, 0x00		; (DO NOT USE XOR HERE!!! IT AFFECTS FLAGS!!)
				; ax = 0, A20 is disabled -> memory wraps around
	je check_a20_exit	;
	mov ax, 0x01		; ax = 1, A20 is enabled -> memory does not wrap
	; Fall through

check_a20_exit:
	pop si
	pop di
	pop es
	pop ds
	popf
	ret

; Function: 	enable_a20
;
; Purpose: Check and try to enable the A20 line
;
; Returns: 	1 in ax on success
;		0 in ax otherwise
enable_a20:
	; If A20 enabled, exit
	call check_a20
	cmp ax, 0x01
	je enable_a20_exit

	; http://www.ctyme.com/intr/rb-1336.htm
	; Return:
	mov ax, 0x2401
	int 0x15

	; If A20 enabled, exit
	call check_a20
	cmp ax, 0x01
	je enable_a20_exit


	; Use osdev method:
	call keyboard_enable_A20

	; If A20 enabled, exit
	call check_a20
	cmp ax, 0x01
	je enable_a20_exit

	; ... Give up
	mov ax, 0x00
	; Fall through
enable_a20_exit:
	ret



[bits 32]
keyboard_enable_A20:
        cli

        call    a20wait
        mov     al,0xAD
        out     0x64,al

        call    a20wait
        mov     al,0xD0
        out     0x64,al

        call    a20wait2
        in      al,0x60
        push    eax

        call    a20wait
        mov     al,0xD1
        out     0x64,al

        call    a20wait
        pop     eax
        or      al,2
        out     0x60,al

        call    a20wait
        mov     al,0xAE
        out     0x64,al

        call    a20wait
        sti
        ret

a20wait:
        in      al,0x64
        test    al,2
        jnz     a20wait
        ret


a20wait2:
        in      al,0x64
        test    al,1
        jz      a20wait2
        ret
