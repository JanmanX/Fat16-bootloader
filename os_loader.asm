[BITS 16]
mov ah, 0x0e    ; function number = 0Eh : Display Character
mov al, 'A'     ; AL = code of character to display
int 0x10        ; call INT 10h, BIOS video service
