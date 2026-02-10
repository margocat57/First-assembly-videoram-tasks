.model tiny

.code
org 100h

start:    mov ax, 0b800h
	  mov es, ax
	  mov bx, 5d*80d*2d

	  mov byte ptr es:[bx], 2ah
	  mov byte ptr es:[bx+1], 10111100b

	  mov ax, 4c00h
	  int 21h

end start
