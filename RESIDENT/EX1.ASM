.286
.model tiny
.code
org 100h

start:      ; устанавливаем на сегмент с векторами прерываний
            push 0
            pop es 
            ; Вектор 09h (клавиатура) лежит по адресу 0:0024h         
            mov bx, 4*09h
            ; меняем код функции прерывания на свой код
            cli
            mov es:[bx], offset New09
            mov ax, cs
            mov es:[bx+2], ax
            sti
            ; Устанавливаем новый обработчик прерывания 09h и делаем программу резидентом
            mov ax, 3100h
            mov dx, offset EOPPP
            shr dx, 4
            inc dx
            int 21h

New09       proc
            push ax bx es
            push 0b800h
            pop es
            mov bx, (80d*5 + 40d)*2
            mov ah, 4eh
            in al, 60h       ; AL = скан-код нажатой клавиши из порта 60h
            mov es:[bx], ax  ; пишем в видеопамять AX = (атрибут + скан-код)
            in al, 61h       ; читаем порт управления клавиатурой
            or al, 80h       ; устанавливаем старший бит (подтверждение)
            out 61h, al      ; отправляем обратно
            and al, not 80h  ; сбрасываем старший бит
            out 61h, al      ; отправляем обратно
            mov al, 20h      ; команда EOI (End Of Interrupt)
            out 20h, al      ; отправляем контроллеру прерываний
            pop es bx ax
            iret
            endp
EOPPP:
end start