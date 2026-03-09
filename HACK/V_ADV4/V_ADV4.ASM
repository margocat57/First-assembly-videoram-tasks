.286
.model tiny
.code
org 100h

locals @@

;--------------------------------------------------------------------
; Macro defines
;--------------------------------------------------------------------
SaveLen          equ  16d              ; length of buffer that protects damaging code when small overflow
ColCorrect       equ  00100000b        ; color when password correct
ColIncorrect     equ  01000000b        ; color when password incorrect
ScreenWidth      equ  80d              
ScreenHeight     equ  25d              
BytesForSymb     equ  2d               ; symbol + attribute
StringStart      equ  12d              ; number of sring in videoram where message displays
PlaceForStr      equ  (ScreenWidth * StringStart + 34d) * BytesForSymb ; place for message start
HelpBufferCap    equ  2710h
; frame defines -----------------------------------------------------
VL               equ  0bah             ; vertical line
HL               equ  0cdh             ; horizontal line
RTC              equ  0bbh             ; right top corner
LTC              equ  0c9h             ; left top corner
RBC              equ  0bch             ; right bottom corner
LBC              equ  0c8h             ; left bottom corner
;--------------------------------------------------------------------

start:           jmp main

;--------------------------------------------------------------------
; Strings with different inputs
;--------------------------------------------------------------------
SecondPasswBufCheck  db "ABCDEFGHIJKLMOPQRST"
SecondPasswLen       equ $ - SecondPasswBufCheck
GreetStr	         db "Enter password:", 0dh, 0ah, "$"
AccessGranted        db "Access granted" 
AccessGrantedLen     equ $ - AccessGranted 
AccessDenied         db "Access denied" 
AccessDeniedLen      equ $ - AccessDenied 
TooLong              db "Too long input$"
;--------------------------------------------------------------------

;--------------------------------------------------------------------
main:     
                mov dx, offset GreetStr ; out input msg
                mov ah, 09h
                int 21h

                call fill_passw_buf
                cmp dx, 0FFFFh
                je no_overflow

                call check_passw
                cmp dx, 0FFFFh
                je passw_incorr

                call process_corr
                mov ax, 4c00h    ; end prog with exit code 0
                int 21h

passw_incorr:   call process_incorr
                mov ax, 4c01h    ; end prog with exit code 1
                int 21h

no_overflow:    mov dx, offset TooLong ; out err msg
                mov ah, 09h
                int 21h
            
		        mov ax, 4c02h    ; end prog with exit code 2
                int 21h
;--------------------------------------------------------------------


;--------------------------------------------------------------------
; Fills buffer for password
;
; Entry: no params
; 
; Exit: dx = FFFFh if buffer overflow occured
;       filled PasswdInput buffer
;
; Destr: di, bx, cx, ax
;--------------------------------------------------------------------
fill_passw_buf  proc 
                mov di, offset PasswdInput
                xor bx, bx      ; bx = 0
                xor cx, cx      ; cx = 0

@@fill_buffer:  xor ax, ax      ; ax = 0

                mov ah, 08h     ; get symbol to al in keyboard
                int 21h

                cmp al, 0dh     ; exit if /r symbol
                je @@exit

                cmp cx, cs:MaxPasswLen ; exit if max buffer len reaches
                je @@exit_no_ovf

@@continue:     mov cs:[di+bx], al  ; put symbol to buffer
                inc bx
                inc cx

                jmp @@fill_buffer

@@exit:         call check_passw2
                ret

@@exit_no_ovf:  mov dx, 0FFFFh
                ret
                endp
;--------------------------------------------------------------------


;--------------------------------------------------------------------
; Checks if password is correct
;
; Entry: no params
; 
; Exit: dx = FFFFh if password incorrect
;
; Destr: di, bx, cx, ax, si
;--------------------------------------------------------------------
check_passw     proc 

                mov di, offset PasswdInput
                mov si, offset CorrectPassw 
                xor bx, bx            ; bx = 0
                xor ax, ax            ; ax = 0
                mov cx, PasswLen      ; cx = PasswLen
                
@@check_loop:   mov al, cs:[di+bx]
                cmp byte ptr cs:[si+bx], al
                jne @@not_correct
                loop @@check_loop

                jmp @@exit

@@not_correct:  mov dx, 0FFFFh
@@exit:         ret
                endp
;--------------------------------------------------------------------


;--------------------------------------------------------------------
; Checks if second password buffer is correct (needs to protect from oberflow)
;
; Entry: no params
; 
; Exit: dx = FFFFh if password incorrect
;
; Destr: di, bx, cx, ax, si
;--------------------------------------------------------------------
check_passw2    proc 

                mov di, offset SecondPasswBufCheck
                mov si, offset SecondPasswBuf
                xor bx, bx            ; bx = 0
                xor ax, ax            ; ax = 0
                mov cx, SecondPasswLen    ; cx = SecondPasswLen
                
@@check_loop:   mov al, cs:[di+bx]
                cmp byte ptr cs:[si+bx], al
                jne @@not_correct
                loop @@check_loop

                jmp @@exit

@@not_correct:  mov dx, 0FFFFh
@@exit:         ret
                endp
;--------------------------------------------------------------------


;--------------------------------------------------------------------
; Getting ready for drawing frame for correct password
;
; Entry: no params
; 
; Exit: videoram updated
;
; Destr: di, cx, ax, si, es
;--------------------------------------------------------------------
process_corr    proc
                
                push 0b800h
                pop es

                xor ax, ax
                mov ah, ColCorrect

                mov si, offset AccessGranted
                mov di, PlaceForStr

                mov cx, AccessGrantedLen

                call draw_message

                ret
                endp
;--------------------------------------------------------------------


;--------------------------------------------------------------------
; Getting ready for drawing frame for incorrect password
;
; Entry: no params
; 
; Exit: videoram updated
;
; Destr: di, cx, ax, si, es
;--------------------------------------------------------------------
process_incorr  proc
                
                push 0b800h
                pop es

                xor ax, ax
                mov ah, ColIncorrect 

                mov si, offset AccessDenied
                mov di, PlaceForStr

                mov cx, AccessDeniedLen

                call draw_message

                ret
                endp
;-------------------------------------------------------------------

;--------------------------------------------------------------------
; Buffers (for input, password and buffer protects small overflow)
;--------------------------------------------------------------------
PasswdInput     db 80h dup(0)
CorrectPassw    db "POLTORASHKA"
PasswLen        equ $ - CorrectPassw
MaxPasswLen     dw 200h
SaveBuffer      db SaveLen dup(0) 
;--------------------------------------------------------------------

;--------------------------------------------------------------------
; Draw top or bottom border line with direction control
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


;---------------------------------------------------------------------
; Main frame drawing function
;
; Entry:  cx = length of text area
;         si = pointer to start of text area in video RAM
;         di = current pointer to video RAM (starting position)
;         es - set to videoram
;
; Exit: No return value (video memory updated)
;
; Destr: ax, cx, di
;---------------------------------------------------------------------
draw_frame      proc

                ; right vertical line
                mov al, VL 
                mov word ptr es:[di], ax
                sub di, ScreenWidth 
                sub di, ScreenWidth 

                ; top right corner element
                mov al, RTC
                mov word ptr es:[di], ax
                sub di, BytesForSymb

                ; top horizontal line
                mov al, HL
                call make_top_bottom

                ; top left corner element
                mov al, LTC
                mov word ptr es:[di], ax
                add di, ScreenWidth 
                add di, ScreenWidth 

                ; left vertical line
                mov al, VL 
                mov word ptr es:[di], ax
                add di, ScreenWidth 
                add di, ScreenWidth 

                ; bottom left corner element
                mov al, LBC
                mov word ptr es:[di], ax
                add di, BytesForSymb

                ; bottom horizontal line
                mov al, HL
                call make_top_bottom

                ; bottom right corner element
                mov al, RBC
                mov word ptr es:[di], ax

                ret
                endp
;---------------------------------------------------------------------

;---------------------------------------------------------------------
; Write text string (ds:[si]) to video RAM (es:[di]) with color attribute and frame
;
; Entry(at stack): di  ---> pointer for memory in video RAM
;                  si  ---> pointer to string in DS
;                  cx     - string length
;
; Exit: String character written to ES:[DI] with color COLW(see macro definitions)
;       di = pointer to next character afteer string
;       si = pointer to start of string in video memory
;
; Exp: es - sets videoram segments
;
; Destr: ax, DF(set to 0), si, (cx, di by draw frame)
;--------------------------------------------------------------------
draw_message    proc

                push cx
                ; drawing string ------------------------------------
str_cpy:	    lodsb		             ; al = ds:[si], si++
		        stosb		             ; es:[di] = al, di++
		        mov byte ptr es:[di], ah ; es:[di]=color
		        inc di		             ; di++
		        loop str_cpy

                ; drawing frame ------------------------------------
                pop cx
                mov si, di
                call draw_frame

                ret
                endp
;--------------------------------------------------------------------

HelpBuffer      db HelpBufferCap dup(0)
SecondPasswBuf  db "ABCDEFGHIJKLMOPQRST"

end start