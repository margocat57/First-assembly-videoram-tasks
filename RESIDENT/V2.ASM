.286
.model tiny

.code
org 100h

locals @@

;-------------------------------------------------------------------------------------------------------------
;-------------------------------------------------------------------------------------------------------------
; Macro const defines
;-------------------------------------------------------------------------------------------------------------
;-------------------------------------------------------------------------------------------------------------
COLF                equ  00111111b        ; color define for frame
COLW                equ  00110000b        ; color define for word
FRAME_H             equ  0bh              ; frame height (11 decimal)
FRAME_L             equ  7h               ; frame length
IDX_TOP_LEFT        equ  0h
IDX_TOP_RIGHT       equ  1h
IDX_BOTTOM_LEFT     equ  2h
IDX_BOTTOM_RIGHT    equ  3h
IDX_HORIZ_LINE      equ  4h
IDX_VERT_LINE       equ  5h
ShiftFromStart      equ 370h              ; (middle of 5th string of videoram) 5d*80d*2d+80d
FrameStart          equ 2CEh              ; (the left top corner of frame) 4d*80d*2d+80d - 2d
FrameWidthBytes     equ 50h               ; 80 decimal
FrameHeightBytes    equ 19h               ; 25 decimal
TimerShift          equ 4d                ; how often are registers updated in timer ticks
;--------------------------------------------------------------------

;-------------------------------------------------------------------------------------------------------------
;-------------------------------------------------------------------------------------------------------------
; Macro defines for some operations
;-------------------------------------------------------------------------------------------------------------
;-------------------------------------------------------------------------------------------------------------

;--------------------------------------------------------------------
; Destr: ax, es, bx
save_old_08h    macro
                ; get the interrupt 09h vector into es:bx
                mov ax, 3508h        
                int 21h       

                mov cs:Old08Offs, bx  
                mov cs:Old08Seg, es 
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
; Note: Should be called after save_old_08h
;
; Destr: ax, dx
set_new_08h     macro
                mov ax, 2508h
                mov dx, offset check_timer

                int 21h
                endm

;--------------------------------------------------------------------
; Note: Should be called after save_old_09h
;
; Destr: ax, dx
set_new_09h     macro
                mov ax, 2509h
                mov dx, offset check_ESC 

                int 21h
                endm


;--------------------------------------------------------------------
exit_err_macro  macro    
                xor ax, ax                  ; ax = 0

                mov dx, offset IncorrectArgs
                mov ah, 09h
                int 21h
            
		        mov ax, 4c01h
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

;--------------------------------------------------------------------



start:          jmp main

;-------------------------------------------------------------------------------------------------------------
;-------------------------------------------------------------------------------------------------------------
; Data for some operations
;-------------------------------------------------------------------------------------------------------------
;-------------------------------------------------------------------------------------------------------------

ConvTable       db "0123456789ABCDEF"
RegsName        db "axbxcxdxsidibpspdsesss"
Old08Offs       dw 0
Old08Seg        dw 0
Old09Offs       dw 0
Old09Seg        dw 0
IncorrectArgs   db "Arguments are incorrect$"
IsFrameShown    db 0                           ;variable shows if frame shown
TimeCnt         db 1                           ;to count timer ticks

frame_elements: 
                db 0c9h                        ; idx 0: left top corner
                db 0bbh                        ; idx 1: right top corner
                db 0c8h                        ; idx 2: left bottom corner
                db 0bch                        ; idx 3: right bottom corner
                db 0cdh                        ; idx 4: horizontal line
                db 0bah                        ; idx 5: vertical line

param_table:    
                db 'TL', IDX_TOP_LEFT,0       ; --TL=xxh - left top corner
                db 'TR', IDX_TOP_RIGHT,0      ; --TR=xxh - right top corner
                db 'BL', IDX_BOTTOM_LEFT,0    ; --BL=xxh - left bottom corner
                db 'BR', IDX_BOTTOM_RIGHT,0   ; --BR=xxh - right bottom corner
                db 'HL', IDX_HORIZ_LINE,0     ; --HL=xxh - horizontal line
                db 'VL', IDX_VERT_LINE,0      ; --VL=xxh - vertical line

param_size       equ 4d
param_count      equ ($ - param_table) / param_size

; buffer for drawing frame before putting it to videoram
DrawBuffer       db  (FrameWidthBytes * FrameHeightBytes * 2) dup(0) 

; buffer to save screen that will be covered to videoram
SaveBuffer       db  (FrameWidthBytes * FrameHeightBytes * 2) dup(0)  

;--------------------------------------------------------------------
;--------------------------------------------------------------------

main:           ;----------------------------------------------------
                ; Set length of sring and string pointer
                ;----------------------------------------------------
                xor cx, cx
                mov cl, byte ptr ds:[80h]     ; cx = ds:[80h]

                mov di, 81h	     ; di = ds:[81h](start cmd line)

                call parce_frame_params
                cmp dx, 0FFFFh
                jne @@resident

                exit_err_macro

@@resident:     save_old_08h

                set_new_08h

                save_old_09h

                set_new_09h
 
                make_resident


;-------------------------------------------------------------------------------------------------------------
;-------------------------------------------------------------------------------------------------------------
; Parce command line params 
;-------------------------------------------------------------------------------------------------------------
;-------------------------------------------------------------------------------------------------------------

;---------------------------------------------------------------------
; Parser of command line parametrs
;
; Entry: cx = string length
;        di ---> pointer to start of string in DS
;
; Exit: (if params set) frame_elements[num_of_param] = user_frame_param
;        dx = FFFFh if syntax error with params occured
; 
; Note: If the users wants to change the default frame parameters, 
;       they must specify named parameters as follows 
;       (for example, for a vertical line) --VL=03h. The allowed names are:
; --TL=xxh - left top corner
; --TR=xxh - right top corner
; --BL=xxh - left bottom corner
; --BR=xxh - right bottom corner
; --HL=xxh - horizontal line
; --VL=xxh - vertical line
;
; Destr: dx(if no syntax error), si, di
;---------------------------------------------------------------------
parce_frame_params proc
                push ax bx cx
                ;----------------------------------------------------
                ; Parce params
                ;----------------------------------------------------
                mov bx, offset frame_elements

@@parce_loop:   cmp cx, 0h
                je @@exit

                xor ax, ax       ; ax = 0
                mov al, ' '      ; al = ' ' (symbol to find)
                call skip_symb   ; skip spaces

                cmp byte ptr ds:[di], 0Dh
                je @@exit

                cmp word ptr ds:[di], '--'
                jne @@exit_err

                add di, 2d
                sub cx, 2d

                cmp byte ptr ds:[di], 0Dh
                je @@exit_err

                call is_name_correct
                cmp si, 0FFFFh
                je @@exit_err

                add di, 2d
                sub cx, 2d

                cmp byte ptr ds:[di], '='
                jne @@exit_err

                inc di
                dec cx

                call htoi
                cmp dx, 0FFFFh
                je @@exit

                mov byte ptr cs:[bx + si], dl
                xor dx, dx                    ; dx = 0
                jmp @@parce_loop

@@exit:         pop cx bx ax
                ret

@@exit_err:     pop cx bx ax
                mov dx, 0FFFFh
                ret
                endp
;---------------------------------------------------------------------


;---------------------------------------------------------------------
; Checks if name of parametr matches with the table of available parameters
;
; Entry: di ---> pointer to letter of string in DS
;      
; Exit: si = 0FFFh - name is not correct
;       si = param_index in param_table if name is correct
;---------------------------------------------------------------------
is_name_correct proc
                push ax bx cx

                mov si, offset param_table 
                mov cx, param_count

@@cmp_loop:     mov bx, cs:[si] 
                cmp word ptr ds:[di], bx
                je @@exit_succ

                add si, param_size
                loop @@cmp_loop
                
@@exit_err:     mov si, 0FFFFh
                pop cx bx ax
                ret

@@exit_succ:    mov si, cs:[si+2]

                pop cx bx ax
                ret
                endp
;---------------------------------------------------------------------

;---------------------------------------------------------------------
; Parse hexadecimal number from command line
;
; Entry: cx = string length
;        di ---> pointer to start of string in DS
;
; Exit: dx - parsed hexadecimal value if parsing succesful,
;       dx = 0FFFFh - if hexadecimal number isn't found
;       di ---> pointer to string without hexidecimal number and separaion symbol
;---------------------------------------------------------------------
htoi            proc
                push ax bx

                xor dx, dx       ; dx = 0
                xor bx, bx       ; bx = 0

@@conv_loop:    mov byte ptr bl, [di] ; bl = ds:[di]

                call is_digit 
                jnc @@check_h

                call calcul_value_check_overflow
                jc @@exit_n_save

                dec cx       ; cx -- (because frame symbols will not be written)
                inc di       ; di++

                jmp @@conv_loop

@@check_h:      call check_h_suffix
                jc @@exit

@@exit_n_save:  pop cx bx ax
                mov dx, 0FFFFh
                ret 

@@exit:         pop bx ax
                ret 
                endp
;--------------------------------------------------------------------

;--------------------------------------------------------------------
; Validate if character in BL is a valid hexadecimal digit
;
; Entry: bl - ASCII character to validate
;
; Exit: CF = 1 - if character is valid hexadecimal digit, 
;       CF = 0 - if character isn't valid hexadecimal digit
; Note: if bl in range 'A'-'F' it will be changed to 'a'-'f'
;
; Note: CF is used because it's one of the few flags 
;        that can be modified with a special instruction
;--------------------------------------------------------------------
is_digit        proc
                cmp bl, '0'
                jb @@not_digit

                cmp bl, '9'
                jbe @@digit

                or bl, 00100000b ;to lower

                cmp bl, 'a'
                jb @@not_digit

                cmp bl, 'f'
                jbe @@digit

@@not_digit:    clc          ; CF = 0
                ret

@@digit:        stc          ; CF = 1
                ret
                endp
;--------------------------------------------------------------------

;--------------------------------------------------------------------
; Calculate hexadecimal value with overflow detection
;
; Entry: dx = current accumulated value (previous digits)
;        bx = value of current hex digit (0-15 from calc_dig_bl)
;
; Exit: CF = 0 - no overflow, 
;       CF = 1 - overflow occurred
;       dx - new accumulated value, calculated by dx = dx * 16 + bx
;--------------------------------------------------------------------
calcul_value_check_overflow  proc

                call convert_letter_to_digit

                shl dx, 4
                add dx, bx
                cmp dx, 0FFh
                ja @@overfow
                clc          ; CF = 0 - no overflow
                ret

@@overfow:      stc          ; CF = 1
                ret
                endp
;--------------------------------------------------------------------


;--------------------------------------------------------------------
; Converts a hexadecimal digit character (0-9, A-F, a-f)
;            to its corresponding numeric value (0-15)
;
; Entry:  bl - ASCII character of hexadecimal digit
;
; Exit: bl - numeric value (0-15) corresponding to input character
;
; Exp:  bl in range: '0'-'9' or 'a'-'f'
;--------------------------------------------------------------------
convert_letter_to_digit proc
                push ax

                xor ax, ax  ; ax = 0

                ; save original in al
                mov al, bl

                ; make bl in range 0-9 
                and bl, 00111111b
                or  bl, 00010000b
                sub bl, '0'

                ; extracts bit 6 from original char, that shows is char letter or not
                and al, 01000000b

                ; converts bit 6 to correction(0 or 9)
                shr al, 6

                mov ah, al
                shl ah, 3

                or al, ah

                ; adds correction to bl
                add bl, al

                pop ax
                ret
                endp
;--------------------------------------------------------------------

;--------------------------------------------------------------------
; Checks if current character is 'h' suffix and skips space after it
;
; Entry: di = pointer to current position in command line
;
; Exit:  CF = 1 if 'h' found and space skipped successfully
;        CF = 0 otherwise
;        di - pointer to string without one symbol 
;        cx - length of string reduced by one
;
; Note:  CF is used because it's one of the few flags 
;         that can be modified with a special instruction
;--------------------------------------------------------------------
check_h_suffix  proc

                cmp bl, 'h'
                jne @@not_h

                ; to next symbol
                inc di
                dec cx            ; because -1 symbol in str

                call check_and_skip_symb
                jnc @@not_h

                stc          ; CF = 1 - h found
                ret

@@not_h:        clc          ; CF = 0
                ret
                endp
;--------------------------------------------------------------------

;--------------------------------------------------------------------
; Check for end symbol and skip if present
;
; Entry: di - pointer to current position in string
;        cx - length of string that will be in frame
;
; Exit:  CF = 1 - end symbol found and skipped, 
;        CF = 0 - no end symbol found
;
; Note: CF is used because it's one  of the few flags 
;        that can be modified with a special instruction
;
; When CF = 1, parametrs(cx and di) were changed by skip_symb
; Destr: bl, al
;--------------------------------------------------------------------
check_and_skip_symb  proc
                mov bl, [di]

                cmp bl, ','
                jne @@no_sep_point
                mov al, ','

                call skip_symb
                stc          ; CF = 1 ; found
                ret

@@no_sep_point: clc          ; CF = 0
                ret
                endp
;--------------------------------------------------------------------

;--------------------------------------------------------------------
; Skip repeated characters in string
;
; Entry: al  = character to skip
;        cx  = length of string (maximum 0FFFh)
;        ds:di = pointer to start of string
;
; Exit:  ds:di = pointer to first character that is NOT al
;        cx = remaining length of string (excluding skipped chars)
; (ex. !!!hello, meow?, al = '!', cx = strlen(hello, meow?))
; Destr: change es to ds
;---------------------------------------------------------------------
skip_symb       proc
                push ax bx
                push dx

                mov dx, ds           ; dx = ds
	            mov es, dx           ; es = dx

		        repe scasb           ; while(cx-- && es:[di++] == al)

                jz @@not_found_diff

                dec di               ; di--(because points to second not space)
                inc cx               ; cx++ (becuse points to first not space)
                
@@not_found_diff:                
                pop dx
                pop bx ax
                ret
                endp
;---------------------------------------------------------------------


;-------------------------------------------------------------------------------------------------------------
;-------------------------------------------------------------------------------------------------------------
; Interrupt handlers
;-------------------------------------------------------------------------------------------------------------
;-------------------------------------------------------------------------------------------------------------

;--------------------------------------------------------------------
; Get symbol from keyboard and compare its scan code with ESC
; (interrupt handler)
;
; Entry: (port) 60h - scan code of current symbol of string
;        cs:IsFrameShown - is frame shown before
; 
; Exit: video memory updated
;
; Note1:If the required key was pressed and if the frame was not visible before, 
;       then the frame is drawn and the corresponding flag is set. 
;       If the frame was previously visible, then the frame is erased 
;       and what was on the screen before the frame is restored.
;
; Note2: If scan code isn't equal to escape to old interrupt handler is called
;--------------------------------------------------------------------
check_ESC       proc
                push sp ax bx cx dx si di bp ds es ss

                in al, 60h      
                mov bl, al

                ; cmp scan code with scan code of esc
                cmp bl, 01h
                jne @@not_esc

                in al, 61h      
                or al, 10000000b     
                out 61h, al  

                and al, 01111111b 
                out 61h, al

                cmp cs:IsFrameShown, 0
                je @@show_frame
                jmp @@show_backgr

@@show_frame:   call save_old_screen
                call show_regs
                mov cs:IsFrameShown, 1
                jmp @@EOI

@@show_backgr:  call show_old_screen
                mov cs:IsFrameShown, 0
                jmp @@EOI

@@not_esc:      pop ss es ds bp di si dx cx bx ax sp
                jmp dword ptr cs:[Old09Offs] 

@@EOI:          
                mov al, 20h     
                out 20h, al  

                pop ss es ds bp di si dx cx bx ax sp

                iret

                endp
;--------------------------------------------------------------------


;--------------------------------------------------------------------
; Timer Interrupt handler
;
; Entry: cs:TimeCnt - the number of timer ticks that have passed % TimerShift
;
; Exit: video memory updated
; cs:TimeCnt = cs:TimeCnt + 1 - if cs:TimeCnt smaller than TimerShift
; cs:TimeCnt = 0 - if cs:TimeCnt equal TimerShift
;
; Note: Every TimerShift tiks, the updated register values are displayed on the screen.
;
; Note: Every timer tick, the contents of the video memory are compared with the reference, 
;       and if there is corruption in the video memory, it is restored.
;
; Note: At the end, the old timer interrupt handler is called.
;--------------------------------------------------------------------
check_timer     proc
                push sp ax bx cx dx si di bp ds es ss

                cmp cs:IsFrameShown, 0
                je @@exit

                mov si, offset DrawBuffer
                add si, FrameStart
                push 0b800h
                pop es
                mov di, FrameStart
                call compare_buffers 

                cmp cs:TimeCnt, TimerShift
                jae @@update_frame

                inc cs:TimeCnt
                jmp @@exit

@@update_frame: call show_regs
                mov cs:TimeCnt,0
                
@@exit:         pop ss es ds bp di si dx cx bx ax sp
                jmp dword ptr cs:[Old08Offs] 

                iret

                endp
;--------------------------------------------------------------------

;-------------------------------------------------------------------------------------------------------------
;-------------------------------------------------------------------------------------------------------------
; Comparison of storage in buffers and videoram
;-------------------------------------------------------------------------------------------------------------
;-------------------------------------------------------------------------------------------------------------

;--------------------------------------------------------------------
; Compare information stored in two buffers
;
; Entry: cs - first buffer segment
;        si - first buffer offset
;        es - second buffer segment
;        di - second buffer offset
;
; Exit: buffers updates via change_elem if the characters do not match
;       nothing in other case
;
; Note: The comparison area has dimensions: width = frame width + 2 (side characters), 
;      height = frame height + 2 (side characters).
;
; Destr: si, di
;--------------------------------------------------------------------
compare_buffers proc
                push ax bx cx

                xor ax, ax          ; ax = 0
                mov bx, FRAME_H
                add bx, 2h

@@process_lines:
                mov cx, FRAME_L
                add cx, 2h

@@cmp_elem:	    mov ax, cs:[si]
                cmp ax, es:[di]
                je @@continue_cmp

                call change_elem
    
@@continue_cmp: add si, 2
                add di, 2
                loop @@cmp_elem

                dec bx
                add si, 8eh       ; si += 80*2 - 9 * 2 = string - (frame_length + 2) 
                add di, 8eh

                cmp bx, 0h
                jne @@process_lines

                pop cx bx ax
                ret
                endp
;--------------------------------------------------------------------

;--------------------------------------------------------------------
; Change one element in video memory with saving to buffer
;
; Entry:  es:di - pointer to position in video memory to change
;         cs:si - pointer to frame element to display
;         SaveBuffer - buffer for saving original data
;
; Exit: Video memory updated
;--------------------------------------------------------------------
change_elem     proc
                push ax bx cx

                mov bx, offset SaveBuffer
                add bx, di
                
                ; save elem to save buffer
                mov ax, es:[di]
                mov cs:[bx], ax
                
                ; show frame element
                mov ax, cs:[si]
                mov es:[di], ax

                pop cx bx ax
                ret
                endp
;--------------------------------------------------------------------

;-------------------------------------------------------------------------------------------------------------
;-------------------------------------------------------------------------------------------------------------
; Data transfer functions between buffers and videoram
;-------------------------------------------------------------------------------------------------------------
;-------------------------------------------------------------------------------------------------------------

;--------------------------------------------------------------------
; Copy information from one place to another place(ex. from draw buffer to videoram)
;
; Entry: ds - source segment
;        si - source offset
;        es - destination segment
;        di - desctination offset
;
; IMPORTANT: if you CHANGE DS before calling function RESTORE IT after call
;
; Exit: buffers updates
; Note: The copy area has dimensions: width = frame width + 2 (side characters), 
;      height = frame height + 2 (side characters).
;
; Destr: si, di, DF(set to 0)
;--------------------------------------------------------------------
copy_to_buffer  proc
                push ax bx cx

                xor ax, ax          ; ax = 0
                mov bx, FRAME_H
                add bx, 2h
                cld		            ; DF=0 (for si+=2 and di+=2) 

@@process_lines:
                mov cx, FRAME_L
                add cx, 2h

@@data_cpy:	    lodsw		        ; ax = ds:[si], si+=2
		        stosw		        ; es:[di] = ax, di+=2
                loop @@data_cpy

                dec bx
                add si, 8eh       ; si += 8eh
                add di, 8eh

                cmp bx, 0h
                jne @@process_lines

                pop cx bx ax
                ret
                endp
;--------------------------------------------------------------------

;--------------------------------------------------------------------
; Wrapper for correctly calling copy_to_buffer with 
; consideration of segments and their restoration
; 
; Entry: no parametrs
;
; Exit: SaveBuffer updated
;
; Destr(by copy_to_buffer): si, di, DF 
;--------------------------------------------------------------------
save_old_screen proc

                ; save old segments
                push ds
                push es

                ; src = videoram
                push 0b800h
                pop ds

                ; dest = buffer
                push cs
                pop es

                mov si, FrameStart

                mov di, offset SaveBuffer
                add di, FrameStart

                call copy_to_buffer

                pop es
                pop ds

                ret
                endp
;--------------------------------------------------------------------

;--------------------------------------------------------------------
; Wrapper for correctly calling copy_to_buffer with 
; consideration of segments and their restoration
; 
; Entry: no parametrs
;
; Exit: Videoram updated
;
; Destr(by copy_to_buffer): si, di, DF 
;--------------------------------------------------------------------
show_old_screen proc

                ; save old segments
                push ds
                push es

                ; src = videoram
                push 0b800h
                pop es

                ; dest = buffer
                push cs
                pop ds

                mov si, offset SaveBuffer
                add si, FrameStart

                mov di, FrameStart

                call copy_to_buffer

                pop es
                pop ds

                ret
                endp
;--------------------------------------------------------------------


;-------------------------------------------------------------------------------------------------------------
;-------------------------------------------------------------------------------------------------------------
; Draw registers and frame
;-------------------------------------------------------------------------------------------------------------
;-------------------------------------------------------------------------------------------------------------

;--------------------------------------------------------------------
; Display the contents of registers ax, bx, cx, dx, si, di, bp, sp, es, ds, ss
;
; Entry: ax, bx, cx, dx, si, di, bp, sp, es, ds, ss values
;
; Exit: No return value (video memory updated)
;
; Destr: si, di, es
;--------------------------------------------------------------------
show_regs       proc

                push cs
                pop es
                mov di, offset DrawBuffer
                add di, ShiftFromStart

                call draw_regs

                mov dx, FRAME_H
                mov cx, FRAME_L
                mov si, di
                call draw_frame

                push 0b800h
                pop es
                mov di, FrameStart

                mov si, offset DrawBuffer
                add si, FrameStart

                push ds

                ; src = code segment
                push cs
                pop ds

                call copy_to_buffer
                pop ds

                ret
                endp
;--------------------------------------------------------------------



;--------------------------------------------------------------------
; Put register name and value to videomemory
;
; Entry: ss:[bp] - pointer to ax value
;        es:di - Starting position in video memory
;
; Exit: No return value (video memory updated)
;
; Exp: registers at stack like this
;      push sp ax bx cx dx si di bp ds es ss cs, called in show_regs
; sp  <-- [bp + 26]
; ax  <-- [bp + 24]
; bx  <-- [bp + 22]
; cx  <-- [bp + 20]
; dx  <-- [bp + 18]
; si  <-- [bp + 16]
; di  <-- [bp + 14]
; bp  <-- [bp + 12]
; ds  <-- [bp + 10]
; es  <-- [bp + 8]
; ss  <-- [bp + 6]
; ret adress <-- [bp + 4]
; bp  <-- [bp + 2]
;
; Destr: di
;--------------------------------------------------------------------
draw_regs       proc
                push bp
                mov bp, sp

                push ax bx cx

                call draw_names
                sub di, 6e0h

                mov cx, FRAME_H
                mov bx, bp   
                add bx, 24d  ; pointer to ax

@@draw_loop:    
                cmp cx, 4h
                je @@put_sp

                mov ax, ss:[bx]
                call draw_reg_value

                sub di, 0Eh
                add di, 0a0h

                sub bx, 2h
                loop @@draw_loop

                add di, 0Eh
                sub di, 0a0h
                pop cx bx ax

                pop bp
                ret

@@put_sp:       mov ax, ss:[bp + 26d]
                add ax, 6h         ; because stack contains flags, cs, ip
                call draw_reg_value

                sub di, 0Eh
                add di, 0a0h

                loop @@draw_loop

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
                mov cx, FRAME_H
                xor bx, bx

                mov ah, COLW

@@draw_loop:    ; put letter in RegsName to buffer
                mov al, cs:[si + bx]
                mov word ptr es:[di], ax 
                
                ; put pointer to next letter in RegsName
                inc bx                       

                ; put letter in RegsName to videoram
                mov al, cs:[si + bx]        
                mov word ptr es:[di + 2], ax 

                ; go to next string
                add di, 0a0h

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
                push ax bx cx

                add di, 4h
                mov bh, COLW
                mov bl, 20h
                mov word ptr es:[di], bx 
                add di, 2h

                mov si, offset ConvTable
                mov cx, 4h

@@draw_loop:    mov bx, ax
                ; get the oldest nibble of bx
                shr bx, 0ch

                ; display the character from the ConvTable corresponding to the nibble
                mov bl, cs:[si + bx]
                mov byte ptr es:[di], bl 
                inc di

                mov byte ptr es:[di], COLW
                inc di

                ; shift ax left by 4 one nibble to position the next nibble for processing
                shl ax, 4h

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
;         dx = frame height
;
; Exit: No return value (video memory updated)
;
; Destr: di
;---------------------------------------------------------------------
draw_frame      proc

                push ax bx cx
                
                mov bx, offset frame_elements

                xor ax, ax   ; ax = 0
                mov ah, COLF

                ; Right vertical line
                mov al, cs:[bx+IDX_VERT_LINE] 
                call make_vert_part

                push IDX_TOP_LEFT IDX_HORIZ_LINE IDX_TOP_RIGHT
                call make_top_bottom
                add di, 0a0h

                ; Left vertical line
                mov al, cs:[bx+IDX_VERT_LINE] 
                call make_vert_part

                push IDX_BOTTOM_RIGHT IDX_HORIZ_LINE IDX_BOTTOM_LEFT
                call make_top_bottom

                pop cx bx ax
                ret 
                endp
;---------------------------------------------------------------------

;--------------------------------------------------------------------
; Draw top or bottom border line with direction control and left/right corners
;
; Entry:    di ---> current pointer in video memory 
;           cx = length of line
;           si ---> pointer to the start of the text in video memory
;           bx ---> pointer to the start of frames table
;           ah = color for element to draw
;(at stack) [sp + 6] - element after drawing line
;           [sp + 4] - element for drawing line
;           [sp + 2] - element before drawing line
;
; Exit:  None (video memory updated)
;
; Destr: DF, di
;---------------------------------------------------------------------
make_top_bottom proc
                push bp
                mov bp, sp

                push ax bx cx

                add bx, ss:[bp + 4]
                mov al, cs:[bx] 
                mov word ptr es:[di], ax 
                sub bx, ss:[bp + 4]

                add bx, ss:[bp + 6]
                mov al, cs:[bx]

                cmp di, si
                jae @@forward
                std                  ; DF = 1(for di--)
                sub di, 2h
                jmp @@draw

@@forward:      cld                  ; DF = 0(for di++)
                add di, 2h

@@draw:         rep stosw            ; while(cx){es[di] = ax, di(+/-)=2 , cx--}

                sub bx, ss:[bp + 6]
                add bx, ss:[bp + 8]
                mov al, cs:[bx] 
                mov word ptr es:[di], ax

                pop cx bx ax

                pop bp
                ret 6h
                endp
;---------------------------------------------------------------------


;--------------------------------------------------------------------
; Draw vertical line of frame
;
; Entry: di ---> current pointer in video memory 
;        si ---> pointer to the start of the text in video memory
;        dx = length of vertical line
;        ax = symbol with attribute to draw
;
; Exit:  None (video memory updated)
;
; Destr: di
;---------------------------------------------------------------------
make_vert_part  proc
                push cx bx ax

                mov cx, dx
                xor bx, bx

                cmp di, si
                jl @@set_direction   
                mov bl, 1h             
@@set_direction:

@@loop_vert:    mov word ptr es:[di], ax
                test bl, bl
                jz @@jump_top
                jmp @@jump_bot

@@jump_top:     add di, 0a0h
                loop @@loop_vert
                jmp @@exit

@@jump_bot:     sub di, 0a0h
                loop @@loop_vert
                jmp @@exit

@@exit:         pop ax bx cx
                ret
                endp
;---------------------------------------------------------------------

end_prog:

end start