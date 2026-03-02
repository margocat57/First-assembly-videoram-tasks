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
IDX_TOP_LEFT        equ  0h
IDX_TOP_RIGHT       equ  1h
IDX_BOTTOM_LEFT     equ  2h
IDX_BOTTOM_RIGHT    equ  3h
IDX_HORIZ_LINE      equ  4h
IDX_VERT_LINE       equ  5h

NumOfRegs           equ  0dh              ; 13 decimal
SpDrawRegPos        equ  NumOfRegs - 5d
RegsStringLength    equ  7h           
FrameHeight         equ  NumOfRegs + 2h   
FrameLength         equ  RegsStringLength + 2h     
StringStartRegs     equ  5h
ShiftFromStart      equ  (StringStartRegs * ScreenWidthBytes + 40d) *2d             ; (middle of 5th string of videoram) 5d*80d*2d+80d
FrameStart          equ  ((StringStartRegs - 1d) * ScreenWidthBytes + 40d - 1d) *2d ; (the left top corner of frame) 4d*80d*2d+80d - 2d
ScreenWidthBytes    equ  50h              ; 80 decimal
ScreenHeightBytes   equ  19h              ; 25 decimal
TimerShift          equ  4h               ; how often are registers updated in timer ticks
NextStringJmp       equ  (ScreenWidthBytes - FrameLength) *2d                     ; si += 80*2 - 9 * 2 = string - (frame_length + 2) 
HotKeyCode          equ  01h
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
                mov dx, offset process_timer

                int 21h
                endm

;--------------------------------------------------------------------
; Note: Should be called after save_old_09h
;
; Destr: ax, dx
set_new_09h     macro
                mov ax, 2509h
                mov dx, offset process_hot_key

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
RegsName        db "axbxcxdxsidibpspdsesssipcs"
IncorrectArgs   db "Arguments are incorrect$"
IsFrameShown    db 0                           ; variable shows if frame shown
TimeCnt         db 0                           ;to count timer ticks

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

param_size      equ 4d
param_count     equ ($ - param_table) / param_size

; buffer for drawing frame before putting it to videoram
DrawBuffer       db  (ScreenWidthBytes * ScreenHeightBytes * 2) dup(0) 

; buffer to save screen that will be covered to videoram
SaveBuffer       db  (ScreenWidthBytes * ScreenHeightBytes * 2) dup(0)  

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
; --TL=xxh, - left top corner
; --TR=xxh, - right top corner
; --BL=xxh, - left bottom corner
; --BR=xxh, - right bottom corner
; --HL=xxh, - horizontal line
; --VL=xxh, - vertical line
;
; Destr: dx(if no syntax error), si, di
;---------------------------------------------------------------------
parce_frame_params proc
                push ax bx cx

                mov bx, offset frame_elements

@@parce_loop:   ; check for loop exit --------------------------------
                cmp cx, 0h
                je @@exit

                xor ax, ax       ; ax = 0
                mov al, ' '      ; al = ' ' (symbol to find)
                call skip_symb   ; skip spaces

                cmp byte ptr ds:[di], 0Dh
                je @@exit

                ; parse '--' ----------------------------------------

                cmp word ptr ds:[di], '--'
                jne @@exit_err

                add di, 2d  ; process next symbol
                sub cx, 2d

                ; parce parametr's name ------------------------------

                cmp byte ptr ds:[di], 0Dh
                je @@exit_err

                call is_name_correct
                cmp si, 0FFFFh
                je @@exit_err

                add di, 2d ; process next symbol
                sub cx, 2d

                ; parce '=' ------------------------------------------

                cmp byte ptr ds:[di], '='
                jne @@exit_err

                inc di  ; process next symbol
                dec cx

                ; parce digit and separation -------------------------

                call htoi
                cmp dx, 0FFFFh
                je @@exit

                ; update frame elements table ------------------------

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

@@cmp_loop:     mov bx, cs:[si]           ; get the name of parametr from param_table 
                cmp word ptr ds:[di], bx  ; compare cmd line element with the name in param_table 
                je @@exit_succ

                add si, param_size        ; go to another element of param_table
                loop @@cmp_loop
                
@@exit_err:     mov si, 0FFFFh
                pop cx bx ax
                ret

@@exit_succ:    mov si, cs:[si+2]         ; get the param_index

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

@@conv_loop:    mov byte ptr bl, ds:[di] ; bl = ds:[di]

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
                mov bl, ds:[di]

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

                mov bx, ds           ; bx = ds
	            mov es, bx           ; es = bx

		        repe scasb           ; while(cx-- && es:[di++] == al)

                jz @@not_found_diff

                dec di               ; di--(because points to second not space)
                inc cx               ; cx++ (becuse points to first not space)
                
@@not_found_diff:                
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
process_hot_key proc
                push ss es ds sp bp di si dx cx bx ax

                ; read letter scan code
                in al, 60h      
                mov bl, al

                ; cmp scan code with scan code of hot key
                cmp bl, HotKeyCode
                jne @@not_esc

                ; send confirmation to PPI that data has been read from the port
                in al, 61h      
                or al, 10000000b     
                out 61h, al  

                ; restore PPI state
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

@@not_esc:      pop ax bx cx dx si di bp sp ds es ss

                ; old 09h interrupt handler
                db 0eah  ; bytecode of command jmp dword ptr
Old09Offs       dw 0
Old09Seg        dw 0

@@EOI:          
                mov al, 20h     
                out 20h, al  

                pop ax bx cx dx si di bp sp ds es ss

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
process_timer   proc
                push ss es ds sp bp di si dx cx bx ax

                cmp cs:IsFrameShown, 0
                je @@exit

                ; compare DrawBuffer and video ram
                mov si, offset DrawBuffer
                add si, FrameStart
                push 0b800h
                pop es
                mov di, FrameStart
                call compare_buffers 

                ; check if frame contents needs updating
                cmp cs:TimeCnt, TimerShift
                jae @@update_frame

                inc cs:TimeCnt
                jmp @@exit

@@update_frame: call show_regs
                mov cs:TimeCnt, 0
                
@@exit:         pop ax bx cx dx si di bp sp ds es ss

                ; old 08h interrupt handler
                db 0eah
Old08Offs       dw 0
Old08Seg        dw 0

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
                mov bx, FrameHeight

@@process_lines:
                mov cx, FrameLength

@@cmp_elem:	    mov ax, cs:[si]
                cmp ax, es:[di]         
                je @@continue_cmp

                call change_elem
    
@@continue_cmp: add si, 2
                add di, 2
                loop @@cmp_elem

                dec bx                    ; decrease number of processed lines
                add si, NextStringJmp     ; go to next string of frame  
                add di, NextStringJmp

                cmp bx, 0h                ; check if all lines are processed
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
                
                ; save element of videoram to save buffer
                mov ax, es:[di]
                mov cs:[bx], ax
                
                ; set frame element to place where frame was damaged
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
;        di - destination offset
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
                mov bx, FrameHeight
                cld		            ; DF=0 (for si+=2 and di+=2) 

@@process_lines:
                mov cx, FrameLength

@@data_cpy:	    lodsw		        ; ax = ds:[si], si+=2
		        stosw		        ; es:[di] = ax, di+=2
                loop @@data_cpy

                dec bx
                add si, NextStringJmp   ; go to next string of frame 
                add di, NextStringJmp

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

                ; dest = SaveBuffer
                push cs
                pop es

                mov si, FrameStart

                mov di, offset SaveBuffer
                add di, FrameStart

                call copy_to_buffer

                ; return all segment values
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

                ; src = SaveBuffer
                push 0b800h
                pop es

                ; dest = video ram
                push cs
                pop ds

                mov si, offset SaveBuffer
                add si, FrameStart

                mov di, FrameStart

                call copy_to_buffer

                ; return all segment values
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
; Destr: si, di
;--------------------------------------------------------------------
show_regs       proc

                push es  ; save es

                ; put registers names and registers values to DrawBuffer

                push cs  ; dest = cs
                pop es

                mov di, offset DrawBuffer  ; set draw start position
                add di, ShiftFromStart

                call draw_regs

                ; put frame elements to DrawBuffer ------------------

                mov dx, NumOfRegs
                mov cx, RegsStringLength

                call draw_frame

                ; copy from DrawBuffer to video ram -----------------

                push 0b800h          ; dest = videoram
                pop es
                mov di, FrameStart

                mov si, offset DrawBuffer
                add si, FrameStart

                push ds

                push cs              ; src = code segment
                pop ds

                call copy_to_buffer
                pop ds               ; restore ds

                pop es               ; restore es

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
;      push ss es ds sp bp di si dx cx bx ax, called in show_regs
; flags      <-- [bp + 34]
; cs         <-- [bp + 32]
; ip         <-- [bp + 30]
; ss         <-- [bp + 28]
; es         <-- [bp + 26]
; ds         <-- [bp + 24]
; sp         <-- [bp + 22]
; bp         <-- [bp + 20]
; di         <-- [bp + 18]
; si         <-- [bp + 16]
; dx         <-- [bp + 14]
; cx         <-- [bp + 12]
; bx         <-- [bp + 10]
; ax         <-- [bp + 8]
; es         <-- [bp + 6] (in previous function)
; ret adress <-- [bp + 4]
; bp         <-- [bp + 2]
;
; Destr: di
;--------------------------------------------------------------------
draw_regs       proc
                push bp
                mov bp, sp

                push ax bx cx

                call draw_names
                sub di, ScreenWidthBytes*2d ; go to last string

                mov cx, NumOfRegs
                mov bx, bp   
                add bx, 32d  ; pointer to cs value

                ; process values from bottom to top

@@draw_loop:    
                cmp cx, SpDrawRegPos  ; check loop counter
                je @@put_sp

                mov ax, ss:[bx]
                call draw_reg_value

@@cont_aft_sp:  sub di, ScreenWidthBytes*2d ; go to place where next register value will be written
                sub di, 0Eh

                sub bx, 2h  ; change pointer to other register value
                loop @@draw_loop

                add di, 0Eh  ; go to right top element of frame
                pop cx bx ax

                pop bp
                ret

@@put_sp:       mov ax, ss:[bx]
                add ax, 12d        ; to get value of stack pointer before interrupt      
                call draw_reg_value

                jmp @@cont_aft_sp

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
                mov cx, NumOfRegs
                xor bx, bx

                mov ah, COLW

                ; process names from top to bottom

@@draw_loop:    ; put letter in RegsName to buffer
                mov al, cs:[si + bx]
                mov word ptr es:[di], ax 
                
                ; put pointer to next letter in RegsName
                inc bx                       

                ; put letter in RegsName to buffer
                mov al, cs:[si + bx]        
                mov word ptr es:[di + 2], ax 

                ; go to next string
                add di, ScreenWidthBytes*2d

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

                ; Draw space between name and value -----------------
                add di, 4h
                mov bh, COLW
                mov bl, 20h
                mov word ptr es:[di], bx 
                add di, 2h

                ; Draw value ----------------------------------------

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
                mov ah, COLF ; set frame color

                push di      ; save di to stack

                ; Top horizontal line with left/right corners
                push IDX_TOP_LEFT IDX_HORIZ_LINE IDX_TOP_RIGHT
                call make_top_bottom
                add di, ScreenWidthBytes*2d ;go to place from which vertical line will be drawn

                ; Left vertical line
                mov al, cs:[bx+IDX_VERT_LINE] 
                call make_vert_part

                pop di      ; return di
                add di, ScreenWidthBytes*2d

                ; Right vertical line
                mov al, cs:[bx+IDX_VERT_LINE] 
                call make_vert_part

                ; Bottom horizontal line with left/right corners
                push IDX_BOTTOM_LEFT IDX_HORIZ_LINE IDX_BOTTOM_RIGHT
                call make_top_bottom
                sub di, ScreenWidthBytes*2d


                pop cx bx ax
                ret 
                endp
;---------------------------------------------------------------------

;--------------------------------------------------------------------
; Draw top or bottom border line with direction control and left/right corners
; Draws from right to left
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

                ; corner element -------------------------------------
                add bx, ss:[bp + 4]
                mov al, cs:[bx] 
                mov word ptr es:[di], ax 
                sub bx, ss:[bp + 4]

                ; horizontal line -------------------------------------

                add bx, ss:[bp + 6]
                mov al, cs:[bx]

                std                  ; DF = 1(for di--)
                sub di, 2h

@@draw:         rep stosw            ; while(cx){es[di] = ax, di(+/-)=2 , cx--}

                ; corner element --------------------------------------

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
; Draws from top to bottom
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

@@loop_vert:    mov word ptr es:[di], ax

                add di, ScreenWidthBytes*2d ; go to next string
                loop @@loop_vert

@@exit:         pop ax bx cx
                ret
                endp
;---------------------------------------------------------------------

end_prog:

end start