;----------------------------------------------------------------
; Program that draws string that is set as command line
;         argument and frame around it
;----------------------------------------------------------------

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
COLF           equ  00001011b        ; color define for frame
COLW           equ  10111100b        ; color define for word
;--------------------------------------------------------------------


start:          
                call main
                jmp exit


;----------------------------------------------------------------
; Main function of progran drawing frame
;
; 1. Skip spaces and parses symbol with which frame will be filles(if has)
; 2. Sets videoram segment and place for title
; 3. Writes title
; 4. Draws frame
;
; Input:  DS:[80h] - command line length
;         DS:[81h] - command line string
;
; Output: None (video memory modified)
;
; Calls:  skip_symb, htoi, setv_place, make_title, draw_frame
;
; Destr: ax, bx, cx, dx, si, di, es
;-----------------------------------------------------------------
main            proc
                mov di, 81h	     ; di = ds:[81h](start cmd line)
                mov al, ' '        ; al = ' ' (symbol to find)

                ;----------------------------------------------------
                ; Skip space and parce symbol for frame(if has)
                ;----------------------------------------------------

                mov cl, byte ptr ds:[80h]     ; cx = ds:[80h]
                call skip_symb       ; skip spaces
                xor dx, dx

                push di
                push cx
                call htoi
                
                mov si, di           ; si = di
                xor ax, ax           ; ax = 0

                ;----------------------------------------------------
                ; Set videoram segment and place for title
                ;----------------------------------------------------

                mov ax, 0002h
                int 10h

                push cx              ; len of string(cx)
                push 5d*80d*2d+80d   ; shift in videoram
                push 0b800h          ; start of videoram
                call setv_place
                add sp, 6         

                xor bx, bx            ; bx = 0

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

                mov bx, 3
                call draw_frame  
                ret 
                endp
;---------------------------------------------------------------------

;--------------------------------------------------------------------
; Skip repeated characters in string
; 
; Descr: Using scasb to skip all leading characters matching al
;        until the first non-matching character is found
;
; Entry: al  = character to skip
;        cx  = length of string (maximum 0FFFh)
;        ds:di = pointer to start of string
;
; Exit:  ds:di = pointer to first character that is NOT al
;        cx = remaining length of string (excluding skipped chars)
;(ex. !!!hello, meow, al = '!', cx = strlen(hello, meow))
; Destr: di, dx, change es to ds, cx
;---------------------------------------------------------------------
skip_symb       proc

                mov dx, ds           ; cx = ds
	          mov es, dx           ; es = cx

		    repe scasb           ; while(cx-- || es:[di++] == ' ')

                dec di               ; di--(because points to second not space)
                inc cx               ; cx++ (becuse points to first not space)
                
                ret
                endp
;---------------------------------------------------------------------

;---------------------------------------------------------------------
; Parse hexadecimal number from command line
;
; Descr: Parses a number from string in format <digits>h<space>.
;        Checks that value is less than 255.
;        Returns 0 in dx if: number not found, value > 255, or format mismatch.
;
; Entry(at stack): [sp + 2] = string length
;                  [sp + 4] ---> pointer to start of string in DS
;
; Exit: dx - parsed hexadecimal value if parsing succesful,
;       dx = 0 - if hexadecimal number isn't found
;
; Destr: bl, di, al, dx
;---------------------------------------------------------------------
htoi            proc

                ; prologue
                push bp
                mov bp, sp

                xor dx, dx       ; dx = 0
                xor bx, bx       ; bx = 0

                mov cx, [bp+4]   ; cx = [bp+4]
                mov di, [bp+6]   ; di = [bp+6]

                jmp @@conv_loop

@@conv_loop:    mov byte ptr bl, [di] ; bl = ds:[di]

                cmp bl, ' '
                jb @@exit_n_save

                call check_parse_dig
                jnc @@check_h

                call calc_val_ch_ovf
                jc @@exit_n_save

                dec cx       ; cx -- (because frame symbols will not be written)
                inc di       ; di++

                jmp @@conv_loop


@@check_h:      cmp bl, 'h'
                jne @@exit_n_save

                call chk_skip_space
                jnc @@exit_n_save

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
; Validate if character in BL is a valid hexadecimal digit
;
; Descr: Validates whether the character in BL is a valid hexadecimal digit.
;        Result is returned in Carry Flag (CF). 
;
; Entry: bl - ASCII character to validate
;
; Exit: CF = 1 - if character is valid hexadecimal digit, 
;       CF = 0 - if character isn't valid hexadecimal digit
;
; Note: CF is used because it's one  of the few x86 flags 
;        that can be modified with a special instruction
;
; Destr: СF
;--------------------------------------------------------------------
check_parse_dig proc
                cmp bl, '0'
                jb @@not_digit

                cmp bl, '9'
                jbe @@digit

                cmp bl, 'A'
                jb @@not_digit

                cmp bl, 'F'
                jbe @@digit

                cmp bl, 'a'
                jb @@not_digit

                cmp bl, 'f'
                jbe @@digit

                jmp @@not_digit

@@not_digit:    clc          ; CF = 0
                ret

@@digit:        stc          ; CF = 1
                ret
                endp
;--------------------------------------------------------------------

;--------------------------------------------------------------------
; Converts a hexadecimal digit character (0-9, A-F, a-f)
;            to its corresponding numeric value (0-15)
;
; Descr: Determines the range of the character in bl (0-9, A-F, or a-f),
;        converts it to its corresponding hexadecimal numeric value,
;        and stores the result back in bl.  
;
; Entry:  bl - ASCII character of hexadecimal digit
;
; Exit: bl - numeric value (0-15) corresponding to input character
;
; Exp:  bl in range: '0'-'9', 'A'-'F', 'a'-'f'
;
; Destr: bl
;--------------------------------------------------------------------
calc_dig_bl     proc

                cmp bl, '9'
                jbe @@sub_0

                cmp bl, 'F'
                jbe @@upper

                cmp bl, 'f'
                jbe @@lower

@@sub_0:        sub bl, '0'
                ret

@@upper:        sub bl, 'A' - 10
                ret

@@lower:        sub bl, 'a' - 10
                ret
                endp
;--------------------------------------------------------------------

;--------------------------------------------------------------------
; Calculate hexadecimal value with overflow detection
; 
; Descr: Updates accumulated value by shifting left 4 bits
;        and adding the value from bx. 
;        Checks for 8-bit overflow.
;
; Entry: dx = current accumulated value (previous digits)
;        bx = value of current hex digit (0-15 from calc_dig_bl)
;
; Exit: CF = 0 - no overflow, 
;       CF = 1 - overflow occurred
;       dx - new accumulated value, calculated by dx = dx * 16 + bx
;--------------------------------------------------------------------
calc_val_ch_ovf  proc

                call calc_dig_bl

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
; Check for space and skip if present
;
; Descr: Changes string pointer: CX--, DI++ (move to next character).
;        Loads the next character into BL and tests if it's a space.
;        If character is not a space: sets Carry Flag to 0 and exits.
;        If character is a space: calls skip_space function
;        to skip all space characters and sets Carry flag to 1
;
; Entry: di - pointer to current position in string
;        cx - length of string that will be in frame
;
; Exit:  CF = 1 - space found and skipped, 
;        CF = 0 - no space found
;
; Note: CF is used because it's one  of the few x86 flags 
;        that can be modified with a special instruction
;
; When CF = 1, parametrs(cx and di) were changed by skip_symb
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


;--------------------------------------------------------------------
; Set video memory segment and center title position
; 
; Descr: Configures memory addressing:
;        ES = first stack parameter (video RAM segment)
;        DI = second stack parameter (center offset)
;        Calculates string start in case of length(third stack parameter):
;          - even length:      DI = DI - length
;          - not even length:  DI = DI - (length - 1)
;
; Entry(at stack): [sp+2]  = start of segment of videoram
;                  [sp+4]  = point of centre of videoram
;                  [sp+6]  = len of string
;
; Exit:  es = video RAM segment
;        di = starting offset in video RAM for centered string
;
; Destr: change es to data in ax, di
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

sub_not_even:   dec cx               ; cx--
                sub di, ax           ; di -= ax
                inc cx               ; cx++

@@epilogue:     pop bp
                ret
                endp
;---------------------------------------------------------------------

;---------------------------------------------------------------------
; Write text string (ds:[si]) to video RAM (es:[di]) with color attribute
;
; Descr:  Copies string to video memory character by character:
;         Zeroes AX before copying
;         Uses lodsb to load character into al
;         Uses STOSB to write character to video memory
;         Sets color attribute from COLW macro after each character
; After copying, restores original cx and sets si to the video memory
; address where the string begins.
;
; Entry(at stack): [sp+6](di)  ---> pointer for memory in video RAM
;                  [sp+4](si)  ---> pointer to string in DS
;                  [sp+2](cx)     - string length
;
; Exit: String character written to ES:[DI] with color COLW(see macro definitions)
;
; Exp:  es - sets videoram segments
;
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
; Draw a single character with color attribute
;
; Descr: If ax is zero, loads the specified symbol into al.
;        Sets ah to the specified color value.
;        Stores ax to video memory at es:[di].
;        If the optional shift parameter is given, increments di by shift bytes.
;
; Entry: sym   - Character to display
;        color - Color attribute byte
;        shift - Optional parameter: number of bytes to add to di
;                after  writing
;
; Exit:  One character written to es:[di] with color at es:[di+1]
;
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
; Sets params to draw horizontal border element with color
;
; Descr: If ax is zero, loads the specified symbol into al.
;        Sets ah to the specified color value.
;        Calls function to draw the border element
;
; Entry: sym - ASCII character to draw
;        color - Color attribute byte for the border
;
; Exit: No return value (video memory updated)
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
; Sets params to draw vertical border element with color
;
; Descr: If ax is zero, loads the specified symbol into al.
;        Sets ah to the specified color value.
;        Calls function to draw the border element
;
; Entry: sym - ASCII character to draw
;        color - Color attribute byte for the border
;
; Exit: No return value (video memory updated)
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
; IMPORTANT: macro VL, RTC, etc will be used for frame only
;            if custom symbol isn't set (dx = 0)
;
; Entry:  dx = custom symbol for frame (0 if using default symbols)
;         cx = length of text area
;         bx = height of frame
;         si = pointer to start of text area in video RAM
;         di = current pointer to video RAM (starting position)
;
; Exit: No return value (video memory updated)
;
; Destr: ax, cx, dx, di
;---------------------------------------------------------------------
draw_frame      proc

                xor ax, ax   ; ax = 0
                mov ax, dx   ; ax = dx

                add cx, 2    ; because the frame does not fit snugle (+1 in left/right)
                add di, 2

                ; calcul shift for staring from the down bottom line 
                call frame_start_shift
            
                call_vert_part VL, COLF

                call_make_one_elem RTC, COLF, -2d

                call_top_bottom HL, COLF

                call_make_one_elem LTC, COLF, 2d*80d

                call_vert_part VL, COLF

                call_make_one_elem LBC, COLF, 2d

                call_top_bottom HL, COLF

                call_make_one_elem RBC, COLF

@@end:
                ret 
                endp
;---------------------------------------------------------------------

;--------------------------------------------------------------------
; Calculate video offset for right horizontal line
;
; Entry: bx = frame height
;        di = current video memory offset
;
; Exit:  di = new position to start drawing vertical line in frame
;
; Destr: dx, di
;--------------------------------------------------------------------
frame_start_shift proc

               push bx
               shr bx, 1

               xor dx, dx   ; dx = 0
               mov dx, bx   ; dx = bx
               shl dx, 5    ; dx = dx*2^5 (= bx*2^5)
                
               push ax      ; save ax

               mov  ax, bx  ; ax = bx
               shl  ax, 7   ; ax = 2^7*ax  (= bx*2^7)
               add  ax, dx  ; ax = ax + dx (= bx*2^5 + bx*2^7)
               add  di, ax  ; di = di + 160*bx (start from bottom to top)

               pop ax       ; return ax to previous value
               pop bx       ; return bx to previous value

               ret
               endp
;--------------------------------------------------------------------

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
; Descr: Compares current di position with si (string start in video ram).
;        Sets bl based on comparison result.
;        Writes a word (character + attribute) to video memory.
;        Moves to next screen line by adding/subtracting 160 bytes.
;
; Entry: di ---> current pointer in video memory 
;        si ---> pointer to the start of the text in video memory
;        bx = length of verticalline
;
; Exit:  None (video memory updated)
;
; Destr: di
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