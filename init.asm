[BITS 16]	; ???
[ORG 0x7c00]
	jmp 0x0000:start_16

start_16:
	xor eax, eax
	mov es, ax
	mov ds, ax

	cli			; Clear interrupt flag
	mov ss, ax
	mov sp, 0x7E00
	sti

	; https://en.wikipedia.org/wiki/BIOS_interrupt_call
	mov ah, 0x0e		; Write a character in TTY
	mov al, 0x23		; '#'
	int 0x10


	; READ FROM DISK
	mov eax, 0x01		; Read 1 sector (512 bytes).
	mov dl, 0x80		; First harddisk
	mov ecx, 0x02		; Sector = 2
	xor dh, dh		; head = 0
	mov bx, 0x7e00		; Destination of read
	call read_sectors_16
	nop

;	mov esi, 0x7E00
;	call print_string


	jmp 0x0000:0x7E00

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
	int 0x13	; Reset and possibly try again
	jnc .top
.end:
	popa
	ret



msg db "Bytes read:", 0xA, 0x0

times 510-($-$$) db 0x00

db 0x55
db 0xaa
