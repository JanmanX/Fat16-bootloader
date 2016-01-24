; 	I use this for debugging...
;	mov ah, 0x0e    ; function number = 0Eh : Display Character
;	mov al, '!'     ; AL = code of character to display
;	int 0x10        ; call INT 10h, BIOS video service

[BITS 16]	; opcode prefix
[ORG 0x7C00]
	jmp short pre_start_16
	nop

; BIOS PARAMETER BLOCK:
; https://stackoverflow.com/questions/34966441/bootloader-printing-garbage-on-real-hardware
; 50 NOPs is probably too much, 25 should be enough.
times 50 db 0x90

pre_start_16:
	jmp 0x0000:start_16	; Bogus BIOSes might load at 0x07C0:0

start_16:
        xor ax, ax
	mov ds, ax
	mov es, ax
        cli                             ; Disable interrupts
        mov ss, ax
        mov sp, 0x7C00
        sti                             ; Enable interrupts
	cld				; Clear Direction Flag

	; Store the drive number
	mov [drive_number], dl
	mov [reg16], dx
	call print_number_16

	; Print loading message
	mov si, msg_loading
	call print_string

	; Extended read
	mov dx, 0x10			; Read 16 * 512 bytes
	xor eax, eax
	xor ebx, ebx
	inc ebx				; Read second sector (sector 1)
	mov cx, 0x7E00			; Start of the os_loader binary
.loop:
	call read_sector
	add ebx, 0x01			; next block
	adc eax, 0x00			; Add 1 to higher sector dword on overflow
	add cx, 0x200			; Move in destination address

	dec dx

	jnz .loop

	; Signature check
	mov eax, [0x7E00]	; Start of the loaded binary
	cmp eax, 0xD105D105	; Check with DIKOS signature
	jne signature_mismatch

	mov eax, [0x7E00 + 0x1FFC] 	; End of the loaded binary minus 4 bytes
	cmp eax, 0xD105D105		; Check with DIKOS signature
	jne signature_mismatch

	mov ax, print_string
	mov bx, print_number_16
	jmp 0x0000:0x7E04


; Signature not matching
signature_mismatch:
	mov si, msg_signature_error
	call print_string

	call print_number_16
	rol eax, 0x10		; Move upper 16 bits to ax
	call print_number_16

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
	mov ah, 0x0E
.repeat:
	lodsb
	cmp al, 0x00
	je .done
	int 0x10
	jmp short .repeat
.done:
	popa
	ret


; read_sector
;
; Reads one sector from a disk and stores them at a specified location
;
; input:	eax = 	High dword of sector
;		ebx = 	Low dword of sector to start from.
; 		es:cx =	Destination address (segment:offset)
; output:	eax = 	High dword of next sector
;		ebx =	Low dword of next sector
; 		es:cx = Points byte after the last read
read_sector:
	pusha
	mov [dap_sector_high], eax
	mov [dap_sector_low], ebx
	mov [dap_segment], es
	mov [dap_offset], cx
	; Sectors to read should already be set to 1
	; DAP size should also already be set


	; BIOS Extended read
.extended_read:
	mov ah, 0x42
	mov dl, [drive_number]
	mov si, dap
	int 0x13
	jnc read_ok	; On success

	mov ah, 0x0e    ; function number = 0Eh : Display Character
	mov al, '!'     ; AL = code of character to display
	int 0x10        ; call INT 10h, BIOS video service

	; On error, reset drives and try again
	xor ax, ax	; ax = 0
	int 0x13	; Reset drives
	jmp .extended_read

read_ok:
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
	call print_string
	ret

msg_read_error db 'Reading from disk failed', 0x0D, 0x0A, 0x00
msg_loading db 'DIKOS Bootloader', 0x0D, 0x0A, 0x00
msg_error db 'Error occured', 0x0D, 0x0A, 0x00
msg_signature_error db 'Signature not matching. EAX: ', 0x0D, 0x0A, 0x00

; Variables
drive_number db 0x00	; Drive number


; Data Address Packet (DAP) for reading from disk using BIOS service int 13h/42h
dap:
dap_size:			; Size of the data address packet.
	db 0x10
dap_reserved:			; Reserved. Should be 0
	db 0x00
dap_block_count:		; Number of blocks to read
	dw 0x01
dap_offset:			; Offset. (Already set with default)
	dw 0x7E00
dap_segment:			; Segment
	dw 0x00
dap_sector_low:			; Lower 32 bits of sector number
	dd 0x01
dap_sector_high:		; Upper 32 bits of sector number
	dd 0x00


; Null the rest of the sector
times 510-($-$$) db 0x00

; Boot signature
db 0x55
db 0xaa
