.model tiny

.code
org 100h 

start:		mov ax, 0b800h
		mov es, ax        ; change segment
		mov di, 5d*80d*2d ; start of 5-th string

		mov cx, 80d       ; set number of iterations in loop
		mov ax, 0bc2ah    ; set symbol and color
		cld		  ; need for di++
		rep stosw         ; while(cx){es[di] = ax; di++; cx--}

		mov ax, 4c00h
		int 21h

end start
