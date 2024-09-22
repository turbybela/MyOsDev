bits 16
org 0x7e00
jmp main
%define ENDL 0x0D, 0x0A
section .text

HelloMsg:           db 'Hello from stage2!', ENDL, 0

main:
    mov si, HelloMsg
    call puts

    cti
    hlt

;
;; Put char
;   Input: al
;
putc:
    push ax
    push bx

    mov ah, 0x0e
    mov bh, 0
    int 0x10

    pop bx
    pop ax
    ret
;

;
;; Put string
;   si - points to string 
puts:        
    push si
    push ax
    push bx         ; Save registers to stack

.loop:
    lodsb           ; Inrements si, moves target of si into al
    or al, al       ; If al is 0, set Zero Flag
    jz .done        ; Jump if zero
    call putc
    jmp .loop
.done:
    pop bx
    pop ax
    pop si

    ret
;
