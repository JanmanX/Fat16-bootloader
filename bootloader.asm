; Bootloader for fat 12
;
; 	I use this for debugging...
;	mov ah, 0x0e    ; function number = 0Eh : Display Character
;	mov al, '!'     ; AL = code of character to display
;	int 0x10        ; call INT 10h, BIOS video service

[BITS 16]	; opcode prefix
[ORG 0x7C00]

%define DEBUG

; BIOS PARAMETER BLOCK (BPB):
; Field			Bytes	Hex-offset
; ----------------------------------------
; OEMIdentifier		8	0x0003
; BytesPerSector	2	0x000B
; SectorsPerCluster	1	0x000D
; ReservedSectors	2	0x000E
; FatCopies		1	0x0010
; RootDirEntries	2	0x0011
; NumSectors		2	0x0013
; MediaType		1	0x0015
; SectorsPerFAT		2	0x0016
; SectorsPerTrack	2	0x0018
; NumberOfHeads		2	0x001A
; HiddenSectors		4	0x001C
; SectorsBig		4	0x0020
; ----------------------------------------

; Only first 3 bytes can be code:
entry:
	jmp short pre_start_16
	nop

OEMIdentifier 		db 'DIKOS0.1'
BytesPerSector 		dw 0x200	; 512 bytes per sector
SectorsPerCluster	db 0x80		;
ReservedSectors 	dw 0x01		; Reserved sectors before FAT (TODO: is this BOOT?)
FATCopies		db 0x02		; Often this value is 2.
RootDirEntries 		dw 0x0800	; Root directory entries
NumSectors		dw 0x0000	;  If this value is 0, it means there are more than 65535 sectors in the volume
MediaType		db 0xF8		; Fixed disk -> Harddisk
SectorsPerFAT		dw 0x0100	; Sectors used by each FAT Table
SectorsPerTrack		dw 0x20		; TODO: Look up? BIOS might change those
NumberOfHeads		dw 0x40		; Does this even matter?
HiddenSectors		dd 0x00
SectorsBig		dd 0x773594		;

; Extended BPB (DOS 4.0)
DriveNumber		db 0x80		; 0 for removable, 0x80 for hard-drive
WinNTBit		db 0x00		; WinNT uses this
Signature		db 0x29		; DOS 4.0 EBPB signature
VolumeID		dd 0x0000D105	; Volume ID. "DIKOS"
VolumeIDString		db "DIKOS BOOT "; Volume ID
SystemIDString		db "FAT12   "   ; File system type, pad with blanks to 8 bytes


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


	; Read FAT table 0 right after bootloader
	mov cx, [SectorsPerFAT]		; Number of sectors to read
	mov ax, [ReservedSectors]	; Read just after reserved sectors
	mov bx, 0x7E00			; target address just after bootloader
	mov [fat_table_address], bx	; Save the target address for later
	call read_sectors

	; Calculate the root directory size
	; root_size = DirEntrySize * DirEntries / BytesPerSector
	mov ax, 0x20			; Size of each directory entry in bytes
	mul word [RootDirEntries]
	div word [BytesPerSector]	; ax = root dir size in sectors
	push ax				; Store root dir size on stack

	; Calculate offset of root directory on drive
	; offset = ReservedSectors + (FATCopies * SectorsPerFAT)
	mov ax, [SectorsPerFAT]
	mul byte [FATCopies]
	add ax, [ReservedSectors]	; ax = offset of root dir on drive
	push ax				; store on stack

	; Calculate the sector offset of the first cluster (used later)
	; Cluster Offset = Reserved + (FATCopies * FATSize) + RootDirSize
	pop bx				; offset of root directory
	pop cx				; size of root directory
	mov ax, bx
	add ax, cx
	mov [data_cluster_offset], ax
	push cx
	push bx

	; Calculate the address off the end of the FAT 0 table in RAM
	; offset = fat_table_address + (SectorsPerFAT * BytesPerSector)
	mov ax, [SectorsPerFAT]
	mul word [BytesPerSector]
	add ax, [fat_table_address]
	mov [root_dir_address], ax	; Store root directory address for later
	mov bx, ax			; bx = target address
	pop ax				; Retrieve the offset on stack
	pop cx				; Retrieve the sector count
	call read_sectors


	times 10 db 0x90
	; Now that root directory is loaded, iterate over each entry and compare
	; with "STAGE2" name
	mov bx, [root_dir_address]	; Base address

.loop_dir_entries:
	mov di, stage2_name
	mov si, bx		; String to compare with
	mov cx, 0x06		; Length of name
	rep cmpsb		; Compare strings
	je .match		; Match found

	add bx, 0x20		; Move to next index
	jl .loop_dir_entries
	jmp error

.match:
	; Match found. Load stage 2
	; bx points to root directory entry of stage2
	mov ax, word [bx + 0x1A]	; offset of the first logical cluster
					; in the directory entry
	mul word [BytesPerSector]
	mov bx, [data_cluster_offset]	; end of Root Directory

.fetch:
	push ax

	xor cx, cx
	mov cl, byte [SectorsPerCluster]
	add ax, [data_cluster_offset]

	times 5 db 0x90

	call read_sectors

	times 5 db 0x90

	mov ah, 0x0e
	mov al, '!'
	int 0x10

	jmp 0x0000:0xDE00


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


; read_sectors
;
; Reads one or more sectors from the disk using BIOS extended read service.
;
; input:	eax = 	LBA sector offset
;		es:bx =	Destination address. (ES should probably be 0)
;		cx = 	Number of sectors to read
;
; output:	eax 	= Next LBA sector offset
; 		es:bx 	= Next address
read_sectors:
	pusha
	mov [dap_sector_low], eax
	mov [dap_segment], es
	mov [dap_offset], bx

.extended_read:
	; BIOS READ
	mov ah, 0x42
	mov dl, [drive_number]
	mov si, dap
	int 0x13
	jnc .read_ok		; No carry flag indicates read OK

	; Indicate error occud
	; TODO: REMOVE
	mov ah, 0x0e
	mov al, '!'
	int 0x10

	; On error, reset drives and try again
	xor ax, ax
	int 0x13
	jmp .extended_read

.read_ok:
	popa			; Restore registers
	inc eax			; Move to next sector
	add bx, 0x200		; Move the destination address
	jnc .no_carry

	; Add 0x1000 to es.
	; It is a segment register, so direct access is not possible
	mov dx, es
	add dh, 0x10	; Add 0x10 to high byte of dh
	mov es, dx
	; Fall through
.no_carry:
	dec cx			; Decrement counter
	jz read_sectors_exit	; Exit if all sectors have been read

	jmp read_sectors

read_sectors_exit:

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
msg_error db 'Error', 0x0D, 0x0A, 0x00

; Variables
drive_number db 0x00		; Drive number
fat_table_address dw 0x0000	; Address of the FAT table
root_dir_address dw 0x0000	; Address of root directory
data_cluster_offset dw 0x0000	; offset of the first cluster


stage2_name 	db 'STAGE2'	; name of stage2 loader in root directory

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
