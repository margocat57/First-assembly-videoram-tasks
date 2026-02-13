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
                mov al, ' '          ; al = ' ' (symbol to find)

                add cl, byte ptr ds:[80h]     ; cx = spaces + ds:[80h](strlen)
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
; Entry(at stack): [sp + 4] ---> pointer to start of string
;                  [sp + 2] ---> pointer to start of string
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

                cmp bl, '9'
                jbe @@parce_digit

                cmp bl, 'A'
                jb @@exit_n_save

                cmp bl, 'F'
                jbe @@parce_upper

                cmp bl, 'a'
                jb @@exit_n_save

                cmp bl, 'f'
                jbe @@parce_lower

                cmp bl, 'h'
                je  @@check_space

                jmp @@exit_n_save

@@check_space:  inc di
                mov bl, [di]
                dec cx            ; because -1 symbol in str

                cmp bl, ' '
                jne @@exit_n_save
                mov al, ' '

                push dx
                call skip_symb
                pop dx
    
                jmp @@exit

@@parce_digit:  sub bl, '0'
                jmp @@get_itog

@@parce_upper:  sub bl, 'A' - 10
                jmp @@get_itog

@@parce_lower:  sub bl, 'a' - 10
                jmp @@get_itog

@@get_itog:     shl dx, 4
                add dx, bx
                inc di
                cmp dx, 0FFh
                dec cx            ; because -1 symbol in str
                ja @@exit_n_save
                jmp @@conv_loop
        
@@exit_n_save:  xor dx, dx
                mov cx, [bp+4]
                mov di, [bp+6]
                jmp @@exit

@@exit:         pop bp
                ret 2d*2d
                endp
;--------------------------------------------------------------------

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
;         bx = length width
; Destr: ax, cx, dx, di
;---------------------------------------------------------------------
draw_frame      proc

                xor ax, ax   ; ax = 0
                mov ax, dx   ; ax = dx

                mov dx, 1
                jmp @@frame

@@frame:        push bx
                call_vert_part VL, COLF

                call_make_one_elem RTC, COLF, -2d

                call_top_bottom HL, COLF

                call_make_one_elem LTC, COLF

                push dx

                /*TODO - подумать как сделать*/
                mul dx, 160d
                add di, dx

                pop dx

                call_vert_part VL, COLF

                call_make_one_elem LBC, COLF, 2d

                call_top_bottom HL, COLF

                call_make_one_elem RBC, COLF

                mov di, 2d

                inc cx
                inc dx

                pop bx
                cmp dx, bx
                ja  @@end
                jmp near ptr @@frame

@@end:
                ret 
                endp
;---------------------------------------------------------------------

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
;        dx = len of vertical segment
; Exit:  nothing returns
; Destr: DF, di, bx
;---------------------------------------------------------------------
make_vert_part  proc
                push cx
                mov cx, dx
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

@@exit:         pop cx
                ret
                endp
;---------------------------------------------------------------------


exit:           xor ax, ax           ; ax = 0
		        mov ax, 4c00h
		        int 21h

end start