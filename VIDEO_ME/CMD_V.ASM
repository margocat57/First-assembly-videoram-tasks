;----------------------------------------------------------------
; Program that draws string that is set as command line
;         argument and frame around it
;----------------------------------------------------------------

.model tiny

.code
org 100h

locals @@

;--------------------------------------------------------------------
; colors defines
COLF           equ  00001011b        ; color define for frame
COLW           equ  00111001b        ; color define for word
;--------------------------------------------------------------------

start:          
                call main

;----------------------------------------------------------------
; Main function of progran drawing frame
;
; Input:  DS:[80h] - command line length
;         DS:[81h] - command line string
;
; IMPORTANT: Before the text, specify the box height and symbols using ;
; Example: program.com 03h;0bah;0bbh;0cdh;0c9h;0c8h;0bch; Meow, Poltorashka
;
; Output: None (video memory modified)
;
; Calls:  skip_symb, htoi, setv_place, make_title, draw_frame
;
; Destr: ax, bx, cx, dx, si, di, es
;-----------------------------------------------------------------
main            proc
                ;----------------------------------------------------
                ; Skip space
                ;----------------------------------------------------
                xor cx, cx
                mov cl, byte ptr ds:[80h]     ; cx = ds:[80h]

                mov di, 81h	     ; di = ds:[81h](start cmd line)

                xor ax, ax       ; ax = 0
                mov al, ' '      ; al = ' ' (symbol to find)

                call skip_symb       ; skip spaces

                ;----------------------------------------------------
                ; Parce frame 
                ;----------------------------------------------------

                ;   1. Height
                ;   2. Vertical line character 
                ;   3. Top-right corner character 
                ;   4. Horizontal line character
                ;   5. Top-left corner character
                ;   6. Bottom-left corner character 
                ;   7. Bottom-right corner character

                mov si, 7   ; si = number of params

fill_symb:      call htoi

                cmp dx, 0FFFFh   
                je exit_err

                push dx

                dec si
                cmp si, 0
                jne fill_symb

                xor ax, ax       ; ax = 0
                mov al, ' '      ; al = ' ' (symbol to find)
                call skip_symb       ; skip spaces

                ;----------------------------------------------------
                ; Set videoram segment and place for title
                ;----------------------------------------------------

                mov si, di           ; si = di

                mov ax, 0002h
                int 10h

                push cx              ; len of string(cx)
                push 5d*80d*2d+80d   ; shift in videoram
                push 0b800h          ; start of videoram
                call setv_place
                add sp, 6d         

                ;----------------------------------------------------
                ; Write title
                ;----------------------------------------------------

                push di
                push si
                push cx
                call make_title

                ;----------------------------------------------------
                ; Draw frame
                ;----------------------------------------------------

                call draw_frame  

exit:           mov ax, 4c00h
		        int 21h

exit_err:       xor ax, ax                  ; ax = 0

                mov dx, offset NoEnoughArgs
                mov ah, 09h
                int 21h
            
		        mov ax, 4c01h
                int 21h

                ret 
                endp
;---------------------------------------------------------------------

;--------------------------------------------------------------------
; Skip repeated characters in string
;
; Entry: al  = character to skip
;        cx  = length of string (maximum 0FFFh)
;        ds:di = pointer to start of string
;
; Exit:  ds:di = pointer to first character that is NOT al
;        cx = remaining length of string (excluding skipped chars)
; (ex. !!!hello, meow, al = '!', cx = strlen(hello, meow))
; Destr: change es to ds
;---------------------------------------------------------------------
skip_symb       proc
                push dx

                mov dx, ds           ; dx = ds
	            mov es, dx           ; es = dx

		        repe scasb           ; while(cx-- && es:[di++] == al)

                dec di               ; di--(because points to second not space)
                inc cx               ; cx++ (becuse points to first not space)
                
                pop dx
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
;
; Destr: bx, al
;---------------------------------------------------------------------
htoi            proc

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

@@exit_n_save:  mov dx, 0FFFFh
                ret 

@@exit:         ret 
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
; Check for space and skip if present
;
; Entry: di - pointer to current position in string
;        cx - length of string that will be in frame
;
; Exit:  CF = 1 - space found and skipped, 
;        CF = 0 - no space found
;
; Note: CF is used because it's one  of the few flags 
;        that can be modified with a special instruction
;
; When CF = 1, parametrs(cx and di) were changed by skip_symb
; Destr: bl, al
;--------------------------------------------------------------------
check_and_skip_symb  proc
                mov bl, [di]

                cmp bl, ';'
                jne @@no_sep_point
                mov al, ';'

                call skip_symb
                stc          ; CF = 1 ; found
                ret

@@no_sep_point: clc          ; CF = 0
                ret
                endp
;--------------------------------------------------------------------


;--------------------------------------------------------------------
; Set video memory segment and center title position
; 
; Descr: Configures memory addressing:
;        es = first stack parameter (video RAM segment)
;        di = second stack parameter (center offset)
;        Calculates string start in case of length(third stack parameter):
;          - even length:      di = di - length
;          - not even length:  di = di - (length - 1)
;
; Entry(at stack): [sp+2]  = start of segment of videoram
;                  [sp+4]  = point of centre of videoram
;                  [sp+6]  = len of string
;
; Exit:  es = video RAM segment
;        di = starting offset in video RAM for centered string
;
; Destr: change es to data in ax
;---------------------------------------------------------------------
setv_place      proc
                ; prologue
                push bp
                mov bp, sp

		        mov es, [bp+4]      ; change segment
                mov di, [bp+6]      ; getting ram centre
                mov cx, [bp+8]      ; getting len of string

                test cx, 1
                jnz sub_not_even
                ; even length:      di = di - length
                sub di, cx          
                jmp @@epilogue

sub_not_even:   ; not even length:  di = di - (length - 1)
                dec cx               ; cx--
                sub di, cx           ; di -= cx
                inc cx               ; cx++

@@epilogue:     pop bp               ; leave is illegal for this processor
                ret
                endp
;---------------------------------------------------------------------

;---------------------------------------------------------------------
; Write text string (ds:[si]) to video RAM (es:[di]) with color attribute
;
; Entry(at stack): [sp+6](di)  ---> pointer for memory in video RAM
;                  [sp+4](si)  ---> pointer to string in DS
;                  [sp+2](cx)     - string length
;
; Exit: String character written to ES:[DI] with color COLW(see macro definitions)
;       di = pointer to next character afteer string
;       si = pointer to start of sting in video memory
;
; Exp: es - sets videoram segments
;
; Destr: ax, DF(set to 0)
;---------------------------------------------------------------------
make_title      proc
                ; epilogue
                push bp
                mov bp, sp

                mov cx, [bp+4]      ; getting cx
                mov si, [bp+6]      ; getting pointer for string
                mov di, [bp+8]      ; getting pointer for memory in videoram

		        xor ax, ax          ; ax = 0
		        cld		            ; DF=0 (for si++ and di++) 
str_cpy:	    lodsb		        ; al = ds:[si], si++
		        stosb		        ; es:[di] = al, di++
		        mov byte ptr es:[di], COLW ; es:[di]=color
		        inc di		        ; di++
		        loop str_cpy

                mov cx, [bp+4]      ; getting cx (old one)
                mov si, [bp+8]      ; si = di(old one)

                pop bp
                ret 3d*2d
                endp
;---------------------------------------------------------------------

;---------------------------------------------------------------------
; Main frame drawing function
;
; Entry:  cx = length of text area
;         si = pointer to start of text area in video RAM
;         di = current pointer to video RAM (starting position)
; (stack) [sp + 14] = Height
;         [sp + 12] = Vertical line character
;         [sp + 10] = Top-right corner character 
;         [sp + 8] = Horizontal line character
;         [sp + 6] = Top-left corner character
;         [sp + 4] = Bottom-left corner character 
;         [sp + 2] = Bottom-right corner character
;
; Exit: No return value (video memory updated)
;
; Destr: ax, cx, di
;---------------------------------------------------------------------
draw_frame      proc

                ; epilogue
                push bp
                mov bp, sp

                mov dx, [bp + 16]

                xor ax, ax   ; ax = 0
                mov ah, COLF

                ; +- 1 символ вправо\влево
                add cx, 2    ; because the frame does not fit snugle (+1 in left/right)
                add di, 2

                ; move down for drawing the side parts of the frame.
                call frame_start_shift

                ; right vertical line
                mov al, [bp + 14]
                call make_vert_part

                ; top right corner element
                mov al, [bp + 12]
                mov word ptr es:[di], ax
                sub di, 2d

                ; top horizontal line
                mov al, [bp + 10]
                call make_top_bottom

                ; top left corner element
                mov al, [bp + 8]
                mov word ptr es:[di], ax
                add di, 2d*80d

                ; left vertical line
                mov al, [bp + 14]
                call make_vert_part

                ; bottom left corner element
                mov al, [bp + 6]
                mov word ptr es:[di], ax
                add di, 2d

                ; bottom horizontal line
                mov al, [bp + 10]
                call make_top_bottom

                ; bottom right corner element
                mov al, [bp + 4]
                mov word ptr es:[di], ax

@@end:
                pop bp
                ret 7d*2d
                endp
;---------------------------------------------------------------------


;--------------------------------------------------------------------
; Calculate video offset for right horizontal line
;
; Entry: dx = frame height
;        di = current video memory offset
;
; Exit:  di = new position to start drawing vertical line in frame
;
; Destr: dx, di
;--------------------------------------------------------------------
frame_start_shift proc
               push dx

               shr dx, 1           ; dx = dx // 2

               push ax

               mov  ax, dx
               shl  dx, 2
               add  dx, ax         ; dx = 5 * dx

               pop ax

               shl dx, 5           ; dx = 32 * dx

               add di, dx          ; di = di + 160*dx (start from bottom to top)
               
               pop dx              ; return dx to previous value

               ret
               endp
;--------------------------------------------------------------------

;--------------------------------------------------------------------
; Draw top or bottom border line with direction control
;
; Entry: di ---> current pointer in video memory 
;        cx = length of line
;        si ---> pointer to the start of the text in video memory
;        ax = symbol to draw
;
; Exit:  None (video memory updated)
;
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
; Draw vertical line of frame
;
; Entry: di ---> current pointer in video memory 
;        si ---> pointer to the start of the text in video memory
;        dx = length of verticalline
;        ax = symbol to draw
;
; Exit:  None (video memory updated)
;
; Destr: di
;---------------------------------------------------------------------
make_vert_part  proc
                push cx
                push bx

                mov cx, dx
                xor bx, bx

                cmp di, si
                jle @@bottom_dir  
                mov bl, 1             
@@bottom_dir:

@@loop_vert:    mov word ptr es:[di], ax
                test bl, bl
                jz  @@jump_to_bot
                jmp @@jump_to_top

@@jump_to_bot:  add di, 80d*2d
                loop @@loop_vert
                jmp @@exit

@@jump_to_top:  sub di, 80d*2d
                loop @@loop_vert
                jmp @@exit

@@exit:         pop bx
                pop cx
                ret
                endp
;---------------------------------------------------------------------


NoEnoughArgs db "No enough arguments or arguments are incorrect$"


end start