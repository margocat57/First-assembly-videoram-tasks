.model tiny

.code
org 100h

start:		mov ax, 0b800h
		mov es, ax
		xor bx, bx ; bx = 0

		mov cx, 25d
LOOP_VERT:
		mov byte ptr es:[bx], 2ah
		mov byte ptr es:[bx+1], 10111100b
		add bx, 80d*2d
		loop LOOP_VERT

		mov ax, 4c00h
		int 21h

end start
