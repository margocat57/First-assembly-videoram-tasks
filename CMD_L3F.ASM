.model tiny

.code
org 100h

locals @@

;--------------------------------------------------------------------
; frame defines
VL             equ  0bah             ; vertical line
HL             equ  0cdh             ; horizontal line
RTC            equ  0bbh             ; right top corner
LTC            equ  0c9h             ; left top corner
RBC            equ  0bch             ; right bottom corner
LBC            equ  0c8h             ; left bottom corner
COLF           equ  10111100b        ; color define for frame
COLW           equ  10111100b        ; color define for word
;--------------------------------------------------------------------


start:          
                call main
                jmp exit

;---------------------------------------------------------------------
; TBD
;---------------------------------------------------------------------
main            proc
                mov di, 81h	     ; di = ds:[81h](start cmd line)
                mov al, ' '        ; al = ' ' (symbol to find)

                mov cl, byte ptr ds:[80h]     ; cx = spaces + ds:[80h](strlen)
                call skip_symb       ; skip spaces
                xor dx, dx

                push di
                push cx
                call htoi
                
                mov si, di           ; si = di
                xor ax, ax           ; ax = 0

                push cx              ; len of string(cx)
                push 5d*80d*2d+80d   ; shift in videoram
                push 0b800h          ; start of videoram
                call setv_place
                add sp, 6            

                xor bx, bx            ; bx = 0

                push di
                push si
                push cx
                call make_title

                mov bx, 3
                call draw_frame  
                ret 
                endp
;---------------------------------------------------------------------

;--------------------------------------------------------------------
; Skip in es:[di] all symbols in al (no more than 0FFFh times)
; Entry: al  = symbol to skip
;        cx  = string len
;        di --> pointer to start of string
; Exit:  di --> pointer to first not symbol in al
;        cx  = len of part of string without symlols in al
;(ex. !!!hello, meow, al = '!', cx = strlen(hello, meow))
; Destr: di, dx, change es to ds
;---------------------------------------------------------------------
skip_symb       proc

                mov dx, ds           ; cx = ds
	          mov es, dx           ; es = cx

		    repe scasb           ; while(cx-- || [di++] == ' ')
                dec di               ; di--(because points to second not space)
                inc cx               ; cx++ (becuse points to first not space)
                
                ret
                endp
;---------------------------------------------------------------------

;---------------------------------------------------------------------
; Parces hex symbol
; Entry(at stack): di ---> pointer to start of string
;                  cx = string len
; Exit: dx - expected symbol(if has)
; Expr: symbol format <symb>h<space>
; Destr: bl, di and al(if symbol was found di is set at start of main string), dx
;---------------------------------------------------------------------
htoi            proc

                push bp
                mov bp, sp

                xor dx, dx
                xor bx, bx

                mov cx, [bp+4]
                mov di, [bp+6]

                jmp @@conv_loop

@@conv_loop:    mov bl, [di]

                cmp bl, ' '
                jb @@exit_n_save

                call check_parse_dig
                jnc @@check_h

                call calcul_value
                jc @exit_n_save

                dec cx       ; because -1 symbol in str
                inc di

                jmp @@conv_loop


@@check_h:      cmp bl, 'h'
                jne @@exit_n_save

                call chk_skip_space
                jnc @exit_n_save

                jmp @@exit

        
@@exit_n_save:  xor dx, dx
                mov cx, [bp+4]
                mov di, [bp+6]
                jmp @@exit

@@exit:         pop bp
                ret 2d*2d
                endp
;--------------------------------------------------------------------

;--------------------------------------------------------------------
; Checks if digit in bl and cacul value in of bl
; Entry: bl - symbol to check
; Exit: CF = 1 - is digit, CF = 0 -isn't digit,
;       bl = value for multyply
; Destr: bl (if value found)
;--------------------------------------------------------------------
check_parse_dig proc
                cmp bl, '0'
                jbe @@not_digit

                cmp bl, '9'
                sub bl, '0'
                jb @@digit

                cmp bl, 'A'
                jb @@not_digit

                cmp bl, 'F'
                sub bl, 'A' - 10
                jbe @@digit

                cmp bl, 'a'
                jb @@not_digit

                cmp bl, 'f'
                sub bl, 'a' - 10
                jbe @@digit

@@not_digit:    clc          ; CF = 0
                ret

@@digit:        stc          ; CF = 1
                ret
                endp
;--------------------------------------------------------------------


;--------------------------------------------------------------------
; Calcul value of dx in light of value of bl
; Entry: dx - old value
;        bx - value of symbol
;        cx - len of string
;        di - pointer to symbol in string
; Exit: CF = 0 - no overflow, CF = 1 - is overflow
;       dx - intermediate value based on the symbol
;--------------------------------------------------------------------
calc_val_ch_ovf  proc

                shl dx, 4
                add dx, bx
                cmp dx, 0FFh
                ja @@overfow
                jmp @@no_overfow

@@overfow:      stc          ; CF = 1
                ret
            
@@no_overfow:   clc          ; CF = 0
                ret
                endp
;--------------------------------------------------------------------

;--------------------------------------------------------------------
; Checks if space after h
; Entry: di - pointer to symbol in string
;        cx - len of string that will be in frame
; Exit: CF = 1 - space found, CF = 0 - space not found,
;              but skip_symb changes cx if space found
; Destr: bl, di, cx, al
;--------------------------------------------------------------------
chk_skip_space  proc
                inc di
                mov bl, [di]
                dec cx            ; because -1 symbol in str

                cmp bl, ' '
                jne @@no_space
                mov al, ' '

                push dx
                call skip_symb
                pop dx
                stc          ; CF = 1
                ret

@@no_space:     clc          ; CF = 0
                ret
                endp



;--------------------------------------------------------------------
; Changes memory segment to video ram (changes es)
; Makes shift to make title in the centre of window
; Entry(at stack): [sp+2]  = start of segment of videoram
;                  [sp+4]  = point of centre of videoram
;                  [sp+6]  = len of string
; Exit:  es  = start of videoram segment
;        di  = start of string in videoram
;        cx  = len of part of string contains symbols in al
; Destr: ax, change es to data in ax, di
;---------------------------------------------------------------------
setv_place      proc

                ; prologue
                push bp
                mov bp, sp

                mov ax, [bp+4]      ; getting ram segment
                mov di, [bp+6]      ; getting ram centre

                ; change segment
		    mov es, ax

                mov cx, [bp+8]      ; getting len of string

                test cx, 1
                jnz sub_not_even
                sub di, cx           ; di = di - cx 
                jmp @@epilogue

sub_not_even:   mov ax, cx           ; ax = cx
                dec ax               ; ax--
                sub di, ax           ; di -= ax

@@epilogue:     pop bp
                ret
                endp
;---------------------------------------------------------------------

;---------------------------------------------------------------------
; Puts text(ds:[si]) to videoram(es:[di])
; Entry(at stack): [sp+6](di)  ---> pointer for memory in videoram
;                  [sp+4](si)  ---> pointer for string
;                  [sp+2](cx)     - string length
; Exit:  does not return anything
; Expr:  es - sets videoram segments
; Destr: ax, di, si, DF(set to 0)
;---------------------------------------------------------------------
make_title      proc

                ; epilogue
                push bp
                mov bp, sp

                mov cx, [bp+4]      ; getting cx
                mov si, [bp+6]      ; getting pointer for string
                mov di, [bp+8]      ; getting pointer for memory in videoram

		    xor ax, ax           ; ax = 0
		    cld		     ; DF=0 (for si++ and di++) 
str_cpy:	    lodsb		     ; al = ds:[si], si++
		    stosb		     ; es:[di] = al, di++
		    mov byte ptr es:[di], COLW ; es:[di]=color
		    inc di		     ; di++
		    loop str_cpy

                mov cx, [bp+4]      ; getting cx (old one)
                mov si, [bp+8]      ; si = di(old one)

                pop bp
                ret 3d*2d
                endp
;---------------------------------------------------------------------


;--------------------------------------------------------------------
; Sets params (in al and al) and draws one symbol
; Entry: sym  = symbol to draw
;        color = color for symbol
;        shift = di shift (not obligatory)
; Exit:  nothing returns
; Destr: di(if shift set)
;---------------------------------------------------------------------
call_make_one_elem macro sym, color, shift
                local ch_col_one_el
                push ax

                test ax, ax
                jnz ch_col_one_el
                mov al, sym

ch_col_one_el:  mov ah, color
                mov word ptr es:[di], ax
                ifnb <shift>          ; if shift not empty
                      add di, shift
                endif                 ; end (ifnb <shift>)
                xor ax, ax

                pop ax

                endm
;---------------------------------------------------------------------


;--------------------------------------------------------------------
; Sets params (in al and al) and calls videoram function
; Entry: sym  = symbol to draw
;        color = color for symbol
; Exit:  nothing returns
;---------------------------------------------------------------------
call_top_bottom macro sym, color
                local ch_col_top_bot
                push ax
    
                test ax, ax
                jnz ch_col_top_bot
                mov al, sym

ch_col_top_bot: mov ah, color
                call make_top_bottom
                xor ax, ax

                pop ax
                endm
;---------------------------------------------------------------------

;--------------------------------------------------------------------
; Sets params (in al and al) and calls videoram function
; Entry: sym  = symbol to draw
;        color = color for symbol
; Exit:  nothing returns
;---------------------------------------------------------------------
call_vert_part  macro sym, color
                local ch_col_vert_pt
                push ax

                test ax, ax
                jnz ch_col_vert_pt
                mov al, sym

ch_col_vert_pt: mov ah, color
                call make_vert_part
                xor ax, ax
    
                pop ax

                endm
;---------------------------------------------------------------------

;---------------------------------------------------------------------
; Сalls functions that draw frame
; (for documentation look at each function)
; Entry:  dx = custom symbol for frame(0 if there are not custom symbs)
;         cx = len
;         bx = height
;         si = pointer to the ram where word starts
;         di = current pointer to ram
; Destr: ax, cx, dx, di
;---------------------------------------------------------------------
draw_frame      proc

                xor ax, ax   ; ax = 0
                mov ax, dx   ; ax = dx

                add cx, 2    ; because the frame does not fit snugle (+1 in left/right)
                inc di

                ; calcul shift for staring from the down bottom line 
                call frame_start_shift
            
                call_vert_part VL, COLF

                call_make_one_elem RTC, COLF, -2d

                call_top_bottom HL, COLF

                call_make_one_elem LTC, COLF

                call_vert_part VL, COLF

                call_make_one_elem LBC, COLF, 2d

                call_top_bottom HL, COLF

                call_make_one_elem RBC, COLF

@@end:
                ret 
                endp
;---------------------------------------------------------------------

;--------------------------------------------------------------------
; Calcul shift for correct draw right horizontal line
; Entry: bx = height
; Exit: correct start position to draw(di)
; Destr: dx, di
;--------------------------------------------------------------------
frame_start_shift proc

               xor dx, dx   ; dx = 0
               mov dx, bx   ; dx = bx
               shl dx, 5    ; dx = dx*2^5 (= bx*2^5)
                
               push ax      ; save ax

               mov  ax, bx  ; ax = bx
               shl  ax, 7   ; ax = 2^7*ax  (= bx*2^7)
               add  ax, dx  ; ax = ax + dx (= bx*2^5 + bx*2^7)
               sub  di, ax  ; di = di - 160*bx

               pop ax       ; return ax to previous value

               ret
               endp
;--------------------------------------------------------------------

;--------------------------------------------------------------------
; Draws bottom/top part of frame
; Entry: ax = (color shl 8) or sym
;        di ---> pointer for memory in videoram
;        cx = len
;        si ---> pointer to the start of the text
; Exit:  nothing returns
; Destr: ax, DF, di
;---------------------------------------------------------------------
make_top_bottom proc
                push cx

                cmp di, si
                jae @@forward
                std                  ; DF = 1(for di--)
                jmp @@draw

@@forward:      cld                  ; DF = 0(for di++)
@@draw:         rep stosw            ; while(cx){es[di] = ax, di(+/-)=2 , cx--}

                pop cx
                ret
                endp
;---------------------------------------------------------------------


;--------------------------------------------------------------------
; Draws vertical part of frame
; Entry: ax = (color shl 8) or sym
;        di ---> pointer for memory in videoram
;        si ---> pointer to the start of the text
;        bx = len of vertical segment
; Exit:  nothing returns
; Destr: DF, di
;---------------------------------------------------------------------
make_vert_part  proc
                push cx
                push bx

                mov cx, bx
                xor bx, bx

                cmp di, si
                jle @@set_direction   
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

@@exit:         pop bx
                pop cx
                ret
                endp
;---------------------------------------------------------------------


exit:           xor ax, ax           ; ax = 0
		    mov ax, 4c00h
		    int 21h

end start