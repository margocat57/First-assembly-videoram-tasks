.286
.model tiny

.code
org 100h

start: 
                mov ax, 1111h
                mov bx, 2222h
                mov cx, 3333h
                mov dx, 0FFFFh

                mov si, 1111h
                mov di, 2222h
                mov bp, 3333h
                mov sp, 4444h

                push 0b800h
                pop es

                call big_delay

                stc              ;   устанавливает CF = 1
                

registers_loop:
                jnc @@no_symb
                mov bx, 8d*80d*2d +84d
                mov byte ptr es:[bx], 2ah
                mov byte ptr es:[bx+1], 11011100b

@@no_symb:      clc                       ; устанавливает CF = 0

                and ax, 0001000100010000b ; обнуляем младший ниббл
                and bx, 0010001000000010b ; обнуляем второй ниббл
                and cx, 0011000000110011b ; обнуляем третий ниббл
                and dx, 0000111111111111b ; обнуляем старший ниббл

                and si, 0001000100010000b ; обнуляем младший ниббл
                and di, 0010001000000010b ; обнуляем второй ниббл
                and bp, 0011000000110011b ; обнуляем третий ниббл
                and sp, 0000010001000100b ; обнуляем старший ниббл

                mov bx, 2222h

                or ax, 0001000100010001b  ; восстанавливаем младший ниббл
                or bx, 0010001000100010b  ; воостанавливаем второй ниббл
                or cx, 0011001100110011b  ; восстанавливаем третий ниббл
                or dx, 1111111111111111b  ; воостанавливаем старший ниббл

                or si, 0001000100010001b  ; восстанавливаем младший ниббл
                or di, 0010001000100010b  ; воостанавливаем второй ниббл
                or bp, 0011001100110011b  ; восстанавливаем третий ниббл
                or sp, 0100010001000100b  ; воостанавливаем старший ниббл

                jmp registers_loop

;-----------------------------------------------------------
; 20 sec delay
; 20 sec = 20 sec * 18.2 = 364 tiks
;-----------------------------------------------------------
big_delay       proc
                push ax cx dx
                
                ; get current time
                mov ah, 00h
                int 1ah              
                
                ; add 364 tiks (20 sec)
                add dx, 364
                adc cx, 0             ; to manage timer overflow
                
                ; save needed time
                push cx
                push dx
                
wait_loop:      
                ; get current time
                mov ah, 00h
                int 1ah
                
                ; compare with needed tome
                pop bx               ; dx
                pop ax               ; cx
                
                cmp dx, bx
                jne not_equal
                cmp cx, ax
                je time_done
                
not_equal:      
                push ax
                push bx
                jmp wait_loop
                
time_done:      
                pop dx cx ax
                ret
                endp

end start