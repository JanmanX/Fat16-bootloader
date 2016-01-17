[BITS 16]	; opcode prefix
[ORG 0x7c00]
	jmp 0x0000:start_16

start_16:
	cli
	xor eax, eax
	mov es, ax
	mov ds, ax
	mov ss, ax
	mov sp, 0x7C00
	sti

	; Store the drive number
	push edx

	; Print drive number
	xor eax, eax
	mov al, dl
	call print_number_16


	; Print loading message
	mov esi, msg_loading
	call print_string


	; Extended read
	mov si, DAP		; address of "disk address packet"
	mov ah, 0x42		; AL is unused
	pop edx			; Get drive number (in DL)
	int 0x13

	jc error

	mov eax, print_string
	mov ebx, print_number_16
	jmp 0x0000:0x7E00

; Generic function for errors
error:
	mov esi, msg_error
	call print_string
	; Fall through to halt
; Halts the system
halt:
	jmp halt


; print_string
;
; Prints a string to screen using BIOS services
;
; IN:
;	esi	= string
print_string:
	pusha
	mov ah, 0x0E

.repeat:
	lodsb
	cmp al, 0x00
	je .done
	int 0x10
	jmp short .repeat
.done:
	; Move to new line
	mov ah, 0x03
	mov bh, 0x00
	int 0x10
	; Move cursor down to new line
	mov ah, 0x02
	mov dl, 0x00
	int 0x10

	popa
	ret


; read_sectors_16
;
; Reads sectors from disk into memory using BIOS services
;
; input:    dl      = drive
;           ch      = cylinder[7:0]
;           cl[7:6] = cylinder[9:8]
;           dh      = head
;           cl[5:0] = sector (1-63)
;           es:bx  -> destination
;           al      = number of sectors
;
; output:   cf (0 = success, 1 = failure)
read_sectors_16:
	pusha
	mov si, 0x02
.top:
	mov ah, 0x02	; Function READ
	int 0x13	; BIOS Interrupt. Sets CF > 0 on error
	jnc .end	; Jump if no carry. (Jump if CF == 0)
	dec si
	jc .top		; Try again
	xor ah, ah
	int 0x13	; Reset harddisk. If suceeded, try reading again
	jnc .top
.end:
	popa
	ret


; print_number_16
;
; Prints a hex value
;
; input: ax 	= number
hex_prefix 	db '0x' 		; Prefix for the hex_str
hex_str 	db '0000', 0x0A, 0x00	; Buffer for our hex value
hex   		db '0123456789ABCDEF'
print_number_16:
	pusha
	mov di, hex_str
	mov si, hex
	mov cx, 0x04
hex_loop:
	; Move the rightmost 4 bits to bx
	rol ax, 0x04
	mov bx, ax
	and bx, 0x0f
	; Find the corresponding ascii value by indexing hex string
	mov bl, [si + bx]
	; Store in output buffer
	mov [di], bl
	inc di
	dec cx
	jnz hex_loop

	mov si, hex_prefix
	call print_string
	popa
	ret

msg_loading db 'bootloader: DIKOS Bootloader', 0x0A, 0x00
msg_error db 'bootloader: Error occured', 0x0A, 0x00


DAP:
	db 0x10
	db 0x00
block_count:
	dw 0x01
db_add:
	dw 0x7E00
	dw 0x00			; Memory page
d_lba:
	dd 0x01
	dd 0x00


; Null the rest of the sector
times 510-($-$$) db 0x00


; Boot signature
db 0x55
db 0xaa
