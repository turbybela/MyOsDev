bits 16
org 0x7C00
section .text
%define ENDL 0x0D, 0x0A
jmp main

section .data

;;;;;;;;;;;;;;;;;;;;;;;;;
; FAT BOOT SECTOR PARAMETERS 

db '01234567890'
FAT_bytes_per_sector:           dw 0
FAT_sectors_per_cluster:        db 0
FAT_num_of_reserved_sectors:    dw 0
FAT_max_root_entries:           dw 0
FAT_total_sector_count:         dw 0
db 0
FAT_sectors_per_fat:            dw 0
FAT_sectors_per_track:          dw 0
FAT_num_of_heads:               dw 0
dd 0
FAT_total_sector_count_f32:     dd 0
dw 0
FAT_boot_signature:             db 0x29
FAT_volume_id:                  dd 0
FAT_volume_label:               db 'NO NAME    '
FAT_file_system_type:           dq 0


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;   Drive Parameters
BootDrive:  db 0xFF

NUMBER_OF_DISK_DRIVES:  db 0xFF
NUMBER_OF_HEADS:        db 0xFF
NUMBER_OF_CYLINDERS:    dw 0xFFFF
NUMBER_OF_SECTORS:      db 0xFF
DRIVE_TYPE:             db 0xFF

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

section .text
halt:           ;; Halting os
    mov si, HaltMsg
    call puts
    cli          ; Disabling interrupts
    hlt
    jmp halt
;

;
;; Hex conversion
;   Input:  al
;   Output: al
hex_conv:
    push bx

    cmp al, 0x09        ; Determine if hex is digit or letter

    jg .hex_letter

    ;; Hex digit
    mov bl, 0x30        ; ASCII 0x30 > 0
    add al, bl
    jmp .hex_done

.hex_letter:
    ;; Hex letter
    mov bl, 0x41        ; ASCII 0x41 > A
    sub al, 0x0A        ; Sub 9 from number
    add al, bl

.hex_done:
    pop bx
    ret
;

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
;; Put hex
;   Input: ax
put_hex:
    push ax     
    push bx 
    push cx
    push dx

    ; Number in A
    mov bx, 0xF000  ; Mask in is B
    mov cx, 0x0004  ; Iterator is in C

.loop:
    dec cl              ; Decrement counter
    ; Correct

    push ax             ; Save number

        and ax, bx          ; Apply mask

        mov dx, 4           ; Get base shift value

        push ax
            mov ax, dx
            mul cl              ; Multiply shift value by current iterator.  
            mov dx, ax   
        pop ax

        push cx
            mov cl, dl
            shr ax, cl          ; Shift output
        pop cx

        mov ah, 0           ; Put ah in known state, al contans hex
        call hex_conv
        call putc           ; Convert and print digit

    pop ax              ; Reset number
    add ch, 4           ; Ready ch for nex iteration.
    shr bx, 4

    or cl, cl           ; Set zero flag
    jnz .loop           ; Loop back if count isn't zero

    pop dx
    pop cx
    pop bx
    pop ax
    ret

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

;
;; Convers LBA sector address into Cylinder-Head-Sector
; Input: 
;       ax - LBA
; Returns:
;       cx [bits 0-5]: sector number
;       cx [bits 6-15]: cylinder
;       dh: head
lba_to_chs:
    push ax
    push dx

    xor dx, dx                          ; dx = 0
    div word [NUMBER_OF_SECTORS]    ; ax = LBA / SectorsPerTrack
                                        ; dx = LBA % SectorsPerTrack

    inc dx                              ; dx = (LBA % SectorsPerTrack + 1) = sector
    mov cx, dx                          ; cx = sector

    xor dx, dx                          ; dx = 0
    div word [NUMBER_OF_HEADS]                ; ax = (LBA / SectorsPerTrack) / Heads = cylinder
                                        ; dx = (LBA / SectorsPerTrack) % Heads = head
    mov dh, dl                          ; dh = head
    mov ch, al                          ; ch = cylinder (lower 8 bits)
    shl ah, 6
    or cl, ah                           ; put upper 2 bits of cylinder in CL

    pop ax
    mov dl, al                          ; restore DL
    pop ax
    ret

;
;; Reset disk system
;
reset_disk_system:
    push ax
    push dx
    push si         ; Saving registes

    mov dl, 1 << 7  ; Drive bit 7, both floppy and drive
    mov ah, 00h     ; Function 00h: Reset Disk System
    int 13h         ; Disk service interrupt

    jnc .success    ; If no carry, operation success

    mov si, Error_DiskFailure
    call puts
    mov al, ah
    mov ah, 0
    call put_hex
    call halt

.success:
    
    pop si          ; Resetting regiters
    pop dx
    pop ax
    ret
;



;
;; Read drive parameters
;
read_drive_params:
    push ax
    push bx
    push cx
    push dx
    push si
    push es
    push di         ; Saving registers

    ;mov dx, 0
    mov cx, 0
    mov bx, 0

    ; --- Parameters ---
    mov ah, 08h         ; Funciton 08h: Read Drive Parameters
    mov dl, [BootDrive] ; Drive index: BootDrive
    mov es, cx   
    mov di, cx          ; Set to 0

    int 13h             ; Disk service interrupt

    jnc .success        ; If no carry, operation success

    mov si, Error_DiskFailure
    call puts
    mov al, ah
    mov ah, 0
    call put_hex
    call halt

.success:
    

    ; ---- Results ----
    mov [NUMBER_OF_DISK_DRIVES], dl

    inc dh
    mov [NUMBER_OF_HEADS], dh

    mov dx, cx
    shr dx, 6
    mov [NUMBER_OF_CYLINDERS], dx

    mov dx, 0x3F
    and cx, dx
    mov [NUMBER_OF_SECTORS], cl

    mov [DRIVE_TYPE], bl

    pop di          ; Resetting registers
    pop es
    pop si
    pop dx
    pop cx
    pop bx
    pop ax

    ret
;



;
;; Read a sector from disk
; INP: 
;   ax: LBS
;   cx: Sectors to read
;   ES:BX - BufferAddressPointer
;
read_drive_sector:
    ; Code - AH: 02h
    ; Params: 
    ;   #Sectors to read: AL
    ;   Cylinder: CX[15:5]
    ;   Sector: CX[5:0]
    ;   Head: DH
    ;   Drive: DL
    ;   Buffer Address Pointer: ES:BX -- SEGMENT * 16 + OFFSET 
    ; Output:
    ;   CF: Carry set on error, clear on success
    ;   AH: Return code ; 00h Success
    ;   AL: #Sectors read

    push ax
    push bx
    push cx
    push dx
    push eS
    push si
    push ds

    
    mov ah, 0x02
    mov al, 0x01
    mov ch, 0
    mov cl, 2
    mov dh, 0
    mov dl, [BootDrive]

    xor bx, bx
    mov es, bx
    mov bx, 0x7E00 ; Sector after bootloader stage 1
    int 13h

    jnc .success
    mov si, Error_DiskFailure
    call puts
    mov al, ah
    mov ah, 0
    call put_hex
    jmp halt

.success:

    pop ds
    pop si
    pop eS
    pop dx
    pop cx
    pop bx
    pop ax
    
    ret
;
;; Main of bootloader stage 1
;
main:  
    cli             ; Disable interrupts

    mov [BootDrive], dl; DL contains drive number.
    mov ax, 0
    mov bx, 0
    mov cx, 0
    mov dx, 0

    ; Data segment setup
    mov ds, ax      ; 0
    mov es, ax      ; 0
    ; Stack setup
    mov ss, ax      ; 0
    mov sp, 0x7C00  ; Beginning of bootloader
    
    sti             ; Enable interrupts

    call reset_disk_system
    call read_drive_params 
    call read_drive_sector

    jmp 0x00:0x7e00 ; jump to stage 2




jmp halt         ; Safety fallback to halt
;

EndLine:            db ENDL, 0
HaltMsg:            db 'HLT.', 0

Error_DiskFailure:    db 'DISK :: Fatal failure.', ENDL, 'Code: ', 0



times 510 - ($ - $$) db 0
dw 0xAA55       ;;Magic number
