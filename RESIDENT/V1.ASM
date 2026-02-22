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

;--------------------------------------------------------------------
; Display space between register name and value 
;
; Descr: Draws a space between register name and its value, 
;        then calls the function to display the register value. 
;        Handles proper cursor positioning
; Entry: es:di - Starting position in video memory
;        ax - Register value to display
;
; Exit:  No return value (video memory updated)
;
; Destr: di
;--------------------------------------------------------------------
draw_reg_space  macro
                add di, 2d*2d
                mov word ptr es:[di + 1], COLW
                add di, 2d
                call draw_reg_value
                endm
;--------------------------------------------------------------------

;--------------------------------------------------------------------
; Shifts di to next string (necessary to draw register values)
;--------------------------------------------------------------------
shift_di        macro
                sub di, 2d*7d
                add di, 2d*80d
                endm
;--------------------------------------------------------------------

;--------------------------------------------------------------------
; Save old value for int 09h
;--------------------------------------------------------------------
save_old_09h    macro
                mov ax, 3509h        
                int 21h              
                mov cs:Old09Offs, bx  
                mov cs:Old09Seg, es 
                endm
;--------------------------------------------------------------------

;--------------------------------------------------------------------
; Install a custom interrupt
; Descr: Installs a custom interrupt handler for INT 09h (keyboard interrupt). 
; Sets the new handler address in the interrupt vector table.
; 
; Note: Should be called after save_old_09h
;       New handler will be called on every keyboard interrupt
;       Uses current code segment as handler's segment
;--------------------------------------------------------------------
set_new_09h     macro
                push ds
                mov ax, 2509h
                push cs
                pop ds
                mov dx, offset check_A 
                int 21h
                pop ds  
                endm
;--------------------------------------------------------------------

;-------------------------------------------------------------------
; Make program DOS resident when terminating
; Descr: Terminates the program but leaves it resident in memory. 
;        Calculates program size in paragraphs and uses DOS function 31h.
;
; Note: Increments the program size value in dx by one paragraph (16 bytes) after size calculation. 
;       This is necessary because the bit shift operation performs integer division that truncates any remainder, 
;       which could lead to serious bugs if not compensated.
;-------------------------------------------------------------------
make_resident   macro
                mov ax, 3100h
                mov dx, offset end_prog
                shr dx, 4
                inc dx
                int 21h
                endm
;--------------------------------------------------------------------
;--------------------------------------------------------------------

;--------------------------------------------------------------------

start:          jmp main

ConvTable       db 30h, 31h, 32h, 33h, 34h, 35h, 36h, 37h, 38h, 39h, 41h, 42h, 43h, 44h, 45h, 46h
RegsName        db "axbxcxdx"

main:          
                save_old_09h

                set_new_09h
 
                make_resident


;--------------------------------------------------------------------
; Get symbol from keyboard and compare its scan code with A
;
; Descr: Reads the scan code from port 60h, 
;        acknowledges the keyboard via port 61h, 
;        compares the received scan code with the English 'A' 
;        key scan code (1Eh), and sets the Carry Flag (CF) if comparison succesful
;
; Entry: (port) 60h - scan code of current symbol of string
;
; Exit:  CF = 1 - the scan code matches English 'A' (1Eh), 
;        CF = 0 - otherwise
;
; Note: CF is used because it's one  of the few flags 
;        that can be modified with a special instruction
;--------------------------------------------------------------------
check_A         proc
                push ax bx cx dx si di bp ds es

                in al, 60h      
                mov bl, al
 
                in al, 61h      
                or al, 10000000b     
                out 61h, al  

                and al, 01111111b 
                out 61h, al 

                cmp bl, 1Eh
                jne @@not_a
                
                call show_regs

@@not_a:         
                mov al, 20h     
                out 20h, al  

                pop es ds bp di si dx cx bx ax 

                pushf
                call dword ptr cs:[Old09Offs]

                iret

                endp
;--------------------------------------------------------------------

;--------------------------------------------------------------------
; Display the contents of registers AX, BX, CX, DX 
;
; Entry: ax, bx, cx, dx values
;
; Exit:  No return value (video memory updated)
;
; Destr: si, di, es
;--------------------------------------------------------------------
show_regs       proc
                push bp
                mov bp, sp

                call set_videoram

                mov dx, [bp + 4]
                mov cx, [bp + 6]
                mov bx, [bp + 8]
                mov ax, [bp + 10]
                call draw_regs

                mov bx, 4d
                mov cx, 7d
                mov si, di
                call draw_frame
                pop bp
                ret

@@exit:         
                ;pushf
                ;call dword ptr cs:[Old09Offs]
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

                mov ax, 0002h
                int 10h 

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
; Descr: Displays register names and their corresponding values in a formatted layout. 
;        First prints register names vertically, then prints each register's value next to its name.
;
; Entry: ax, bx, cx, dx - Register values to display (passed via stack)
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

                draw_reg_space
                shift_di

                mov ax, bx
                draw_reg_space
                shift_di

                mov ax, cx
                draw_reg_space
                shift_di

                mov ax, dx
                draw_reg_space

                pop cx bx ax
                ret
                endp
;--------------------------------------------------------------------

;---------------------------------------------------------------------
; Displays names of registers in video memory.
; 
; Descr:  Puts to videomemory register names letter by letter on each iteration from the RegsName table.
;         Displays the names of four registers (AX, BX, CX, DX) vertically in a column.
;
; Exit: No return value (video memory updated)
;
; Destr: di
;---------------------------------------------------------------------
draw_names      proc
                push ax bx cx

                mov si, offset RegsName
                mov cx, 4
                xor bx, bx

                mov ah, COLW

@@draw_loop:    mov al, cs:[si + bx]
                mov word ptr es:[di], ax
                
                inc bx
                mov al, cs:[si + bx]
                mov word ptr es:[di + 2], ax

                add di, 80d*2d
                inc bx

                loop @@draw_loop

                pop cx bx ax

                ret
                endp
;---------------------------------------------------------------------

;---------------------------------------------------------------------
; Displays the value of a register in video memory as a 4-digit hexadecimal number.
; 
; Descr:  At each iteration, extracts 4 bits from the register starting from the most significant nibble, 
;         uses ConvTable to find the corresponding ASCII character, 
;         and displays it on screen with the COLW attribute.
;
; Entry:  ax = value
;         di = current pointer to video RAM (starting position)
;
; Exit: No return value (video memory updated)
;
; Destr: di
;---------------------------------------------------------------------
draw_reg_value  proc
                push ax bx cx
                mov si, offset ConvTable
                mov cx, 4

@@draw_loop:    mov bx, ax
                shr bx, 12

                mov bl, cs:[si + bx]
                mov byte ptr es:[di], bl
                inc di

                mov byte ptr es:[di], COLW 
                inc di

                shl ax, 4

                loop @@draw_loop

                pop cx bx ax

                ret
                endp
;---------------------------------------------------------------------

;---------------------------------------------------------------------
; Main frame drawing function
;
; Descr: Shifts right by one character, moves down(call frame_start_shift) 
;        for drawing the side parts of the frame.
;        Frame drawing sequence:
;          1. Right vertical line
;          2. Top right corner element
;          3. Top horizontal line
;          4. Top left corner element
;          5. Left vertical line
;          6. Bottom left corner element
;          7. Bottom horizontal line
;          8. Bottom right corner element
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

                ; drawing frame
                mov al, 0bah
                call make_vert_part

                mov al, 0bbh
                mov word ptr es:[di], ax
                sub di, 2d

                mov al, 0cdh
                call make_top_bottom

                mov al, 0c9h
                mov word ptr es:[di], ax
                add di, 2d*80d

                mov al, 0bah
                call make_vert_part

                mov al, 0c8h
                mov word ptr es:[di], ax
                add di, 2d

                mov al, 0cdh
                call make_top_bottom

                mov al, 0bch
                mov word ptr es:[di], ax

                pop cx bx ax
                ret 
                endp
;---------------------------------------------------------------------

;--------------------------------------------------------------------
; Draw top or bottom border line with direction control
;
; Descr: Compares current di position with si (string start in video memory).
;        Sets Direction Flag (DF) based on comparison result.
;        Uses rep stosw to draw horizontal lines in the appropriate direction.
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
; Descr: Compares current di position with si (string start in video ram).
;        Sets bl based on comparison result.
;        Writes a word (character + attribute) to video memory.
;        Moves to next screen line by adding/subtracting 160 bytes.
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

Old09Offs   dw 0
Old09Seg    dw 0

end_prog:

end start

