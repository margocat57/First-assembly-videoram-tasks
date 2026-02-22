.model tiny
;--------------------------------------------------------------------
; frame defines
VL             equ  0bah             ; vertical line
HL             equ  0cdh             ; horizontal line
RTC            equ  0bbh             ; right top corner
LTC            equ  0c9h             ; left top corner
RBC            equ  0bch             ; right bottom corner
LBC            equ  0c8h             ; left bottom corner
COLF           equ  10111100b        ; color define for frame
COLW           equ  10111100b        ; color define for word
;--------------------------------------------------------------------

.code
org 100h

start:		mov si, 81h	     ; si = ds:[81h](start cmd line)
		mov di, 81h	     ; di = ds:[81h](start cmd line)

		mov cx, ds           ; cx = ds
		mov es, cx           ; es = cx
		xor cx, cx           ; cx = 0

;---------------------------------------------------------------------
; skip spaces asm version
		mov cx, 0FFFFh       ; cx = max counter
		mov al, ' '          ; al = ' ' (symbol to find)
		repe scasb           ; while(cx-- || [di++] == ' ')
		
		dec di               ; di-- (becuse di = first not space)
		sub di, si           ; di = di - si

		xor cx, cx           ; cx = 0
		mov cl, ds:[80h]     ; cl = ds:[80h](strlen)
		sub cx, di           ; cx = cx - di(strlen - spaces)

		add si, di           ; si = si + di(start + spaces)
;---------------------------------------------------------------------
		xor ax, ax           ; ax = 0
		xor di, di           ; di = 0

		mov ax, 0b800h
		mov es, ax

;---------------------------------------------------------------------
; make shift
		xor ax, ax           ; ax = 0
		mov ax, cx           ; ax = cx
		shr ax, 1            ; ax = ax // 2 (len str//2)

		mov di, 5d*80d*2d+80d
		sub di, ax           ; di = di - ax
;----------------------------------------------------------------------
; make |
		mov word ptr es:[di-2],(COLF shl 8) or VL  ;  es:[di] = VL(|), es:[di+1] = COL

;-----------------------------------------------------------------------
; make label	
		push cx              ; save cx
		xor ax, ax           ; ax = 0

		cld		     ; DF=0 (for si++ and di++) 
str_cpy:	lodsb		     ; al = ds:[si], si++
		stosb		     ; es:[di] = al, di++
		mov byte ptr es:[di], COLW ; es:[di]=color
		inc di		     ; di++
		loop str_cpy

;--------------------------------------------------------------------------
; make |
		mov word ptr es:[di], (COLF shl 8) or VL ; es:[di] = VL(|), es:[di+1] = COL

;--------------------------------------------------------------------------
; make right top corner

		sub di, 80d*2d       ; di = di - 80d*2d (di -= string)
		mov word ptr es:[di],(COLF shl 8) or RTC ; es:[di] = RTC, es:[di+1] = COL
		sub di, 2             ; di-=2

;--------------------------------------------------------------------------
; make top frame
		pop cx
		push cx

		xor ax, ax           ; ax = 0
		mov ax, (COLF shl 8) or HL ; ax = COLF + HL (concatenation)

		std                  ; DF = 1(for di--)
                rep stosw            ; while(cx){es[di] = ax, di-=2 , cx--}
;--------------------------------------------------------------------------
; make left top corner

		mov word ptr es:[di], (COLF shl 8) or LTC; es[di] = LTC, es[di+1] = COL
;--------------------------------------------------------------------------
; make left bottom corner

		add di, 80d*2d*2d    ; di = 80d*2d*2d (go to bottom str)
		mov word ptr es:[di], (COLF shl 8) or LBC; es[di] = LBC, es[di+1] = COL
		add di, 2
;---------------------------------------------------------------------------
; make bottom frame
		pop cx

		xor ax, ax
		mov ax,(COLF shl 8) or HL ; ax = COLF + HL (concatenation)

		cld                       ; DF = 0 (for di++)
		rep stosw                 ; while(cx){es[di]=ax, di+=2; cx--}
;---------------------------------------------------------------------------
; make right bottom corner

		mov word ptr es:[di], (COLF shl 8) or RBC ; es[di] = RBC, es[di+1] = COL
;---------------------------------------------------------------------------
; end program	
		xor ax, ax           ; ax = 0
		mov ax, 4c00h
		int 21h

end start
