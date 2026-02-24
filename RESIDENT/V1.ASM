.286
.model tiny

.code
org 100h

locals @@

;--------------------------------------------------------------------
; colors defines
COLF           equ  00111111b        ; color define for frame
COLW           equ  00110000b        ; color define for word
;--------------------------------------------------------------------

;--------------------------------------------------------------------
; Macro defines

shift_di        macro
                sub di, 2d*7d
                add di, 2d*80d
                endm

;--------------------------------------------------------------------
; Destr: ax, es, bx
save_old_09h    macro
                ; get the interrupt 09h vector into es:bx
                mov ax, 3509h        
                int 21h       

                mov cs:Old09Offs, bx  
                mov cs:Old09Seg, es 
                endm

;--------------------------------------------------------------------
; Note: Should be called after save_old_09h
;
; Destr: ax, dx
set_new_09h     macro
                ; install custom (save i) 09h interrupt
                mov ax, 2509h
                mov dx, offset check_ESC 
                int 21h
                endm

;-------------------------------------------------------------------
; Note: Increments the program size value in dx by one paragraph (16 bytes) after size calculation. 
;       This is necessary because the bit shift operation performs integer division that truncates any remainder, 
;       which could lead to serious bugs if not compensated.
make_resident   macro
                ; calculate size in paragraphs
                mov dx, offset end_prog
                shr dx, 4
                inc dx

                ; make program DOS resident when terminating
                mov ax, 3100h
                int 21h
                endm

start:          jmp main

ConvTable       db "0123456789ABCDEF"
RegsName        db "axbxcxdx"
Old09Offs       dw 0
Old09Seg        dw 0

main:          
                save_old_09h

                set_new_09h
 
                make_resident


;--------------------------------------------------------------------
; Get symbol from keyboard and compare its scan code with ESC
;
; Entry: (port) 60h - scan code of current symbol of string
;
; Exit:  CF = 1 - the scan code matches ESC(01h),
;        CF = 0 - otherwise
;
; Note: CF is used because it's one  of the few flags 
;        that can be modified with a special instruction
;--------------------------------------------------------------------
check_ESC       proc
                push ax bx cx dx si di bp ds es

                ; read scan code from keyboard
                in al, 60h      
                mov bl, al
 
                ; signal keyboard controller that character was read
                in al, 61h      
                or al, 10000000b     
                out 61h, al  

                ; reset port to initial state
                and al, 01111111b 
                out 61h, al 

                ; cmp scan code with scan code of esc
                cmp bl, 01h
                jne @@not_esc
                
                call show_regs
                jmp @@EOI

@@not_esc:     
                ; call old interrupt handler    
                pushf
                call dword ptr cs:[Old09Offs]

@@EOI:          ; a signal to the interrupt controller that interrupt handling is complete
                mov al, 20h     
                out 20h, al  

                pop es ds bp di si dx cx bx ax 

                iret

                endp
;--------------------------------------------------------------------

;--------------------------------------------------------------------
; Display the contents of registers AX, BX, CX, DX 
;
; Entry: ax, bx, cx, dx values
;
; Note: At previous function: (VERY IMPORTANT because hard to debug UPDATE IF CHANGE)
; push ax bx cx dx si di bp ds es
; ax  <-- bp + 20
; bx  <-- bp + 18
; cx  <-- bp + 16
; dx  <-- bp + 14
; si  <-- bp + 12
; di  <-- bp + 10
; bp  <-- bp + 8
; ds  <-- bp + 6
; es  <-- bp + 4
; ret adress <-- bp + 2
; bp  <-- bp
;
; Exit:  No return value (video memory updated)
;
; Destr: si, di, es
;--------------------------------------------------------------------
show_regs       proc
                push bp
                mov bp, sp

                call set_videoram

                mov dx, [bp + 14]
                mov cx, [bp + 16]
                mov bx, [bp + 18]
                mov ax, [bp + 20]
                call draw_regs

                mov bx, 4d
                mov cx, 7d
                mov si, di
                call draw_frame

                pop bp
                ret
                endp
;--------------------------------------------------------------------

;--------------------------------------------------------------------
; Clear terminal and set place for registers
;
; Exit: es - video memory segment
;       di - shift in video memory
;--------------------------------------------------------------------
set_videoram    proc
                push ax bx cx

                ; Set text mode via int 10h
                mov ax, 0002h
                int 10h 

                ; Set es to videoram and di at place in it
                push 0b800h
                push 5d*80d*2d+80d
                pop di
                pop es

                pop cx bx ax
                ret
                endp
;--------------------------------------------------------------------

;--------------------------------------------------------------------
; Put register name and value to videomemory
;
; Entry: ax,bx, cx, dx - Register values to display (passed via stack)
;        es:di - Starting position in video memory
;
; Exit: No return value (video memory updated)
;
; Destr: di
;--------------------------------------------------------------------
draw_regs       proc
                push ax bx cx

                call draw_names
                sub di, 4d*2d*80d

                call draw_reg_value
                shift_di

                mov ax, bx
                call draw_reg_value
                shift_di

                mov ax, cx
                call draw_reg_value
                shift_di

                mov ax, dx
                call draw_reg_value

                pop cx bx ax
                ret
                endp
;--------------------------------------------------------------------

;---------------------------------------------------------------------
; Displays names of registers in video memory.
;
; Exit: No return value (video memory updated)
;
; Destr: di, si
;---------------------------------------------------------------------
draw_names      proc
                push ax bx cx

                mov si, offset RegsName
                mov cx, 4
                xor bx, bx

                mov ah, COLW

@@draw_loop:    ; put letter in RegsName to videoram
                mov al, cs:[si + bx]
                mov word ptr es:[di], ax
                
                ; put pointer to next letter in RegsName
                inc bx                       

                ; put letter in RegsName to videoram
                mov al, cs:[si + bx]        
                mov word ptr es:[di + 2], ax

                ; go to next string
                add di, 80d*2d

                ; put pointer to next letter in RegsName
                inc bx

                loop @@draw_loop

                pop cx bx ax

                ret
                endp
;---------------------------------------------------------------------

;---------------------------------------------------------------------
; Displays the value of a register in video memory as a 4-digit hexadecimal number.
;
; Entry:  ax = value
;         di = current pointer to video RAM (starting position)
;
; Exit: No return value (video memory updated)
;
; Destr: di
;---------------------------------------------------------------------
draw_reg_value  proc
                add di, 2d*2d
                mov word ptr es:[di + 1], COLW
                add di, 2d
                
                push ax bx cx
                mov si, offset ConvTable
                mov cx, 4

@@draw_loop:    mov bx, ax
                ; get the oldest nibble of bx
                shr bx, 12

                ; display the character from the ConvTable corresponding to the nibble
                mov bl, cs:[si + bx]
                mov byte ptr es:[di], bl
                inc di

                mov byte ptr es:[di], COLW 
                inc di

                ; shift ax left by 4 one nibble to position the next nibble for processing
                shl ax, 4

                loop @@draw_loop

                pop cx bx ax

                ret
                endp
;---------------------------------------------------------------------

;---------------------------------------------------------------------
; Main frame drawing functions
;
; Entry:  cx = length of text area
;         si = pointer to start of text area in video RAM
;         di = current pointer to video RAM (starting position)
;         bx = frame height
;
; Exit: No return value (video memory updated)
;
; Destr: di
;---------------------------------------------------------------------
draw_frame      proc

                push ax bx cx
                
                xor ax, ax   ; ax = 0
                mov ah, COLF

                ; Right vertical line
                mov al, 0bah
                call make_vert_part

                ; Top right corner element
                mov al, 0bbh
                mov word ptr es:[di], ax
                sub di, 2d

                ; Top horizontal line
                mov al, 0cdh
                call make_top_bottom

                ; Top left corner element
                mov al, 0c9h
                mov word ptr es:[di], ax
                add di, 2d*80d

                ; Left vertical line
                mov al, 0bah
                call make_vert_part

                ; Bottom left corner element
                mov al, 0c8h
                mov word ptr es:[di], ax
                add di, 2d

                ; Bottom horizontal line
                mov al, 0cdh
                call make_top_bottom

                ; Bottom right corner element
                mov al, 0bch
                mov word ptr es:[di], ax

                pop cx bx ax
                ret 
                endp
;---------------------------------------------------------------------

;--------------------------------------------------------------------
; Draw top or bottom border line with direction control
;
; Entry: di ---> current pointer in video memory 
;        cx = length of line
;        si ---> pointer to the start of the text in video memory
;
; Exit:  None (video memory updated)
;
; Destr: DF, di
;---------------------------------------------------------------------
make_top_bottom proc
                push ax bx cx

                cmp di, si
                jae @@forward
                std                  ; DF = 1(for di--)
                jmp @@draw

@@forward:      cld                  ; DF = 0(for di++)
@@draw:         rep stosw            ; while(cx){es[di] = ax, di(+/-)=2 , cx--}

                pop cx bx ax
                ret
                endp
;---------------------------------------------------------------------


;--------------------------------------------------------------------
; Draw vertical line of frame
;
; Entry: di ---> current pointer in video memory 
;        si ---> pointer to the start of the text in video memory
;        bx = length of vertical line
;
; Exit:  None (video memory updated)
;
; Destr: di
;---------------------------------------------------------------------
make_vert_part  proc
                push cx bx ax

                mov cx, bx
                xor bx, bx

                cmp di, si
                jl @@set_direction   
                mov bl, 1             
@@set_direction:

@@loop_vert:    mov word ptr es:[di], ax
                test bl, bl
                jz @@jump_top
                jmp @@jump_bot

@@jump_top:     add di, 80d*2d
                loop @@loop_vert
                jmp @@exit

@@jump_bot:     sub di, 80d*2d
                loop @@loop_vert
                jmp @@exit

@@exit:         pop ax bx cx
                ret
                endp
;---------------------------------------------------------------------

end_prog:

end start

