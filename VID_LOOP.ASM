; output red star in horizontal
.model tiny

.code
org 100h

start:		mov ax, 0b800h
		mov es, ax
		mov bx, 5d*80d*2d

		mov cx, 80d

L:		mov byte ptr es:[bx], 2ah
		mov byte ptr es:[bx+1], 10111100b
		add bx, 2d
		loop L

		mov ax, 4c00h
		int 21h

end start

		