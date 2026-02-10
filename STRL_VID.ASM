;display string in video ram with own-made loop 
.model tiny

.data      
  CRLF            equ 0dh, 0ah
  str_meow	  db 'Hello, meow!',CRLF,'$'

.code
org 100h
	
start:		mov di, offset str_meow
		
		push di

count_symb:     mov al, [di]
		inc di
		inc cx	
		cmp al, '$'	
		jne count_symb
		
		pop di
		dec cx

		mov ax, 0b800h
		mov es, ax
		mov bx, 5d*80d*2d

		jcxz ret_ex_code

loop_display:  	mov ax, ds:[di]
		mov es:[bx], ax
		mov byte ptr es:[bx+1], 10111100b
		add bx, 2d
		inc di
		loop loop_display

ret_ex_code:	mov ax, 4c00h
		int 21h

end start





		



				
