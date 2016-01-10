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

	; Print loading message
	mov esi, msg_loading
	call print_string

	; READ FROM DISK
	mov eax, 0x01		; Read 1 sector (512 bytes).
	mov dl, 0x80		; First harddisk
	mov ecx, 0x02		; Sector = 2
	xor dh, dh		; head = 0
	mov bx, 0x7E00		; Destination of read
	call read_sectors_16

	; Check for errors (If carry flag is set)
	jc error

	mov esi, msg_loaded
	call print_string
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


msg_loading db 'DIKOS Bootloader - Loading', 0x0A, 0x00
msg_loaded db 'Loading complete. Jumping', 0x0A, 0x00
msg_error db 'Error occured', 0x0A, 0x00

times 510-($-$$) db 0x00

db 0x55
db 0xaa
