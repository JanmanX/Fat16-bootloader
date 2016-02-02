; Bootloader for fat 12
;
; 	I use this for debugging...
;	mov ah, 0x0e    ; function number = 0Eh : Display Character
;	mov al, '!'     ; AL = code of character to display
;	int 0x10        ; call INT 10h, BIOS video service

[BITS 16]	; opcode prefix
[ORG 0x0000]

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
	jmp short start_16
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


;pre_start_16:
;	jmp 0x0000:start_16	; Bogus BIOSes might load at 0x07C0:0

start_16:
        cli                             ; Disable interrupts
	xor ax, ax
        mov ss, ax
	mov sp, 0x7C00
	mov ax, 0x07C0
	mov ds, ax
        mov es, ax
	sti                             ; Enable interrupts
	cld				; Clear Direction Flag


	; Store the drive number
	mov [drive_number], dl
	mov [reg16], dx
	call print_number_16

	; Print loading message
	mov si, msg_loading
	call print_string


	; Calculate root directory sector offset
	; sector = Reserved + FATCopies * SectorsPerFAT
	mov ax, [FATCopies]
	mul word [SectorsPerFAT]
	add ax, [ReservedSectors]
	mov [root_dir_offset], ax	; Store the sector offset

	mov [reg16], ax
	call print_number_16

	; Calculate the data cluster offset
	; offset = root_dir_offset + root_dir_size
	; root_dir_size = (RootDirEntries * 0x20) / BytesPerSector
	;  	NOTE, to avoid overflow, do this instead
	; root_dir_size = RootDirEntries / (BytesPerSector / 0x20)
	xchg ax, bx			; root_dir_offset in bx

	mov ax, [BytesPerSector]
	mov cx, 0x20
	div cx
	xchg ax, cx			; cx = BytesPerSector / 0x20
	mov ax, [RootDirEntries]
	div cx				; ax = RootDirEntries / BytesPerSector / 0x20
	add ax, bx			; ax = root_dir_size + root_dir_offset

	; Data cluster sector offset should be 0x281
	; Thus, the first cluster sector offset is:
	; 0x281 + (FAT_Entry - 2) * SectorsPerCluster
	; 0x281 + (3 - 2) * SectorsPerCluster
	; 0x281 + SectorsPerCluster
	; 0x281 + 0x80
	; 0x301.
	; In bytes, that is 0x301 * 0x200 = 0x60200
	mov [data_cluster_offset], ax

	mov [reg16], ax
	call print_number_16


	; Iteratively read sectors from root directory and search for stage 2
	xor dx, dx
.loop:
	mov ax, [root_dir_offset]
	add ax, dx			; Read sector offset dx + root_dir_offset
	mov bx, 0x200			; Read to 0x7E00 (just after bootloader)
	mov cx, 0x01			; Read 1 sector
	push dx				; Save dx for later
	call read_sectors


	; Search for stage 2
	mov bx, 0x200			; First entry
	mov ax, bx
	add ax, [BytesPerSector]	; When si = bx, we have iterated over
					; all entries.
.loop_dir_entries:
	mov di, stage2_name		; Load name of stage 2 ("STAGE2")
	mov cx, 0x06			; Length of string to compare
	mov si, bx
	rep cmpsb 			; Compares byte at address SI and DI
	je .match			; Jump when match found

	; No match, move to next entry
	add bx, 0x20
	cmp ax, bx			; If ax = bx, no more entries
	jne .loop_dir_entries

	; Move to next sector and try again
	pop dx
	inc dx

	cmp dx, 0x80			; Have we iterated over whole root dir?
	jne .loop

	; At this point, we have iterated over whole root directory without
	; success. Exit
	jmp error

.match:
	mov ah, 0x0e    ; function number = 0Eh : Display Character
	mov al, '!'     ; AL = code of character to display
	int 0x10        ; call INT 10h, BIOS video service

	; ES:BX points to the root directory entry
	mov ax, word [bx + 0x1A]	; Retrieve the first cluster number

; - Load cluster (ax) to disk starting 0x8000
; - Load FAT0
; - Check next cluster
; - Exit if none
; - Repeat
	mov bx, 0x0400
	mov [stage2_cur_offset], bx
.lloop:
	push ax			; Store FAT INDEX


	; Calculate the Cluster sector offset
	; offset = data_cluster_offset + (FAT_INDEX - 2) * SectorsPerCluster
	sub ax, 0x02
	mul byte [SectorsPerCluster]
	add ax, [data_cluster_offset]	; Starting offset

	mov cx, [SectorsPerCluster]	; Number of sectors to read
	mov bx, [stage2_cur_offset]	; offset to read to
	call read_sectors

	add bx, [SectorsPerCluster]	; Increment bx
	mov [stage2_cur_offset], bx	; save current offset


	; To load the file, we have to lookup the FAT table.
	; To avoid loading the whole table, we will only load the section of it
	; that contains the information about our cluster.
	; For each sector in FAT table, there are 256 entries of clusters.
	; 	ex. To load FAT entries on cluster 300:
	;		300 / 256 = 1 (rounded down).
	;		300 % 256 = 44
	;	Thus, we load the first sector and look at entry 44.
	pop ax				; Retrieve FAT INDEX
	xor dx, dx
	mov cx, 256
	div cx
	push dx				; Store remainder

	; ax is the quotient
	; 0x7d03
	add ax, [ReservedSectors]	; Compute actual offset to read
	mov cx, 0x01			; Read only one sector

	xor bx, bx
	mov es, bx
	mov bx, 0x7E00			; Read to 0x7E00. Root_dir is not needed

	call read_sectors

	; Retrieve the next cluster
	pop bx
	shl bx, 0x01			; Multiply by 2 as every entry is 2 bytes
	add bx, 0x200			; Add bytes preceeding (boot sector)
	mov ax, word [bx]


	mov [reg16], ax
	call print_number_16


	; test the
	jmp 0x0000:0x8000



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
;		es:bx =	Destination address.
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

msg_read_error db 'Reading failed', 0x0D, 0x0A, 0x00
msg_loading db 'DIKOS Bootloader', 0x0D, 0x0A, 0x00
msg_error db 'Error', 0x0D, 0x0A, 0x00

; Variables
drive_number db 0x00		; Drive number
root_dir_offset dw 0x0000	; Address of root directory
data_cluster_offset dw 0x0000	; offset of the first cluster
stage2_name 	db 'STAGE2'	; name of stage2 loader in root directory
stage2_cur_offset dw 0x0000	; Current offset in memory

; Data Address Packet (DAP) for reading from disk using BIOS service int 13h/42h
dap:
dap_size:			; Size of the data address packet.
	db 0x10
dap_reserved:			; Reserved. Should be 0
	db 0x00
dap_block_count:		; Number of blocks to read
	dw 0x01
dap_offset:			; Offset. (Already set with default)
	dw 0x0000
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
