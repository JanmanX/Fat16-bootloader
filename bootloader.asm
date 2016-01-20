;	mov ah, 0x0e    ; function number = 0Eh : Display Character
;	mov al, '!'     ; AL = code of character to display
;	int 0x10        ; call INT 10h, BIOS video service

[BITS 16]	; opcode prefix
[ORG 0x7C00]
	jmp 0x0000:start_16

start_16:
	cli
	xor ax, ax
	mov es, ax
	mov ds, ax
	mov ss, ax

	; Note to future selves: Zeroing FS and GS breaks the BIOS on some machines
;	mov fs, ax
;	mov gs, ax

	mov sp, 0x7C00
	sti

	; Store the drive number
	mov [drive_number], dl

	mov ah, 0x0e    ; function number = 0eh : display character
	mov al, '!'     ; al = code of character to display
	int 0x10        ; call int 10h, bios video service



	; Print drive number
	xor ax, ax
	mov al, dl
	call print_number_16
	mov ah, 0x0e    ; function number = 0eh : display character
	mov al, '!'     ; al = code of character to display
	int 0x10        ; call int 10h, bios video service


	; Print loading message
	mov si, msg_loading
	call print_string
	mov ah, 0x0e    ; function number = 0eh : display character
	mov al, '!'     ; al = code of character to display
	int 0x10        ; call int 10h, bios video service


	; Extended read
	mov si, dap		; address of "disk address packet"
	mov ah, 0x42		; AL is unused
	mov dx, [drive_number]		; Get drive number (in DL)
	int 0x13
	jc read_error


	; Signature check
	mov eax, [0x7E00]	; Start of the loaded binary
	cmp eax, 0xD105D105	; Check with DIKOS signature
	jne signature_mismatch


	mov ax, print_string
	mov bx, print_number_16
	jmp 0x0000:0x7E04


; Reading failed
read_error:
	mov si, msg_read_error
	call print_string
	jmp error

; Signature not matching
signature_mismatch:
	mov si, msg_signature_error
	call print_string
	jmp error

; Generic function for errors
error:
	mov si, msg_error
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
;	si	= string
print_string:
	pusha
.repeat:
	mov ah, 0x0E
	xor bx, bx
	mov bl, [text_color]

	lodsb
	cmp al, 0x00
	je .done
	int 0x10
	jmp short .repeat
.done:
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
hex_str 	db '0000', 0x0D, 0x0A, 0x00	; Buffer for our hex value
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

msg_read_error db 'bootloader: Reading from disk failed', 0x0D, 0x0A, 0x00
msg_loading db 'bootloader: DIKOS Bootloader', 0x0D, 0x0A, 0x00
msg_error db 'bootloader: Error occured', 0x0D, 0x0A, 0x00
msg_signature_error db 'bootloader: Signature not matching', 0x0D, 0x0A, 0x00

; Variables
drive_number db 0x00	; Drive number
text_color db 0x0A	; Color attribute when printing


dap:
	db 0x10
	db 0x00
block_count:
	dw 0x01			; Read one block at once
dap_offset:
	dw 0x7E00		; The OS loader is 8kib (8192 bytes)
dap_segment:
	dw 0x00			; DAP
d_lba:
	dd 0x01
	dd 0x00


; Null the rest of the sector
times 510-($-$$) db 0x00


; Boot signature
db 0x55
db 0xaa
