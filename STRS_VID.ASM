.model tiny

.data
  str_meow  db 'Hello, meow!$'

.code
org 100h

start:		mov si, offset str_meow
		mov di, si

		mov cx, 0FFFFh            ; counter for repne

		mov al, '$'
		cld			  ; for di++
		repne scasb               ; while(cx-- || [di++] != al){}

		sub di, si                ; di = di - si (strlen)
		dec di                    ; di--(not to output $)
		mov cx, di                ; put strlen to cx

		mov ax, 0b800h
		mov es, ax
		mov di, 5d*80d*2d

		cld                       ; for si++ and di++
str_vram_cpy:   lodsb                     ; al = ds:[si], si++
		stosb		          ; es:[di] = al, di++
		mov byte ptr es:[di], 10111100b ; es:[di] = color
		inc di			  ; di++;
		loop str_vram_cpy	  ; while(cx), cx--

		mov ax, 4c00h
		int 21h
end start



		