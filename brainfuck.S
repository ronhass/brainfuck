;------------------------------------------------------------------------------
; File:			brainfuck.S
; Description:	Emulator for the brainfuck programming language.
;
; Notes:		Calling convention is fastcall: 4 first parameters are in the
;				registers (ax, bx, cx, dx), the rest are in the stack and the
;				return value is in ax. Other registers should not be changed.
;				If the size of the parameter is only one-byte, the value should
;				be hold in the lower part of the register.
;------------------------------------------------------------------------------

[BITS 16]
global _start

; the size of each of the 3 buffers - program, input and data. 
%define INPUT_SIZE 0x4000

;------------------------------------------------------------------------------
; Code section
;------------------------------------------------------------------------------
section .text

_start:
main:
	enter 3*INPUT_SIZE, 0

	; print welcome message
	call newline
	call newline
	call newline
	mov ax, welcome_msg
	call println

	.start:
	; initialize program buffer
	lea ax, [bp-INPUT_SIZE]
	xor bx, bx
	mov cx, INPUT_SIZE
	call memset

	; get program
	mov ax, enter_prog_msg
	call println
	lea ax, [bp-INPUT_SIZE]
	mov bx, INPUT_SIZE
	call get_input
	test ax, ax
	jnz .get_prog_fail
	
	.restart:
	; initialize input and data buffers
	mov ax, bp
	sub ax, 3*INPUT_SIZE ; we can't do "lea ax, [bp-3*INPUT_SIZE]" because we overflow
	xor bx, bx
	mov cx, 2*INPUT_SIZE
	call memset

	; get input
	mov ax, enter_input_msg
	call println
	lea ax, [bp-2*INPUT_SIZE]
	mov bx, INPUT_SIZE
	call get_input
	test ax, ax
	jnz .get_input_fail

	; finally, emulate program!
	mov ax, emulate_msg
	call println
	lea ax, [bp-INPUT_SIZE] ; program buffer
	lea bx, [bp-2*INPUT_SIZE] ; input buffer
	mov cx, bp
	sub cx, 3*INPUT_SIZE ; data buffer
	mov dx, INPUT_SIZE ; data buffer size
	call emulate
	test ax, ax
	jnz .emulate_fail

	; emulation succeeded
	call newline
	mov ax, emulate_end_msg
	call println
	jmp .end

	; failures:
	.emulate_fail:
	mov ax, emulate_fail_msg
	call println
	jmp .end
	.get_prog_fail:
	mov ax, get_prog_fail_msg
	call println
	jmp .end
	.get_input_fail:
	mov ax, get_input_fail_msg
	call println
	jmp .end

	; prompt for another emulation:
	.end:
	call newline
	mov ax, menu_msg
	call println
	call newline
	xor ah, ah
	int 0x16 ; getchar
	cmp al, 's'
	jz .start ; if 's', start again
	cmp al, 'r'
	jz .restart ; if 'r', restart with the same program

	; otherwise, print goodbye and hang
	mov ax, goodbye_msg
	call println

	leave
	jmp $

;------------------------------------------------------------------------------
; Function:		print
; Description:	Print a null-terminated string.
; 
; :param: str - Pointer to a null-terminated string.
;
; Note:			This function gets its input from the code segment, because
;				we print constants from our binary.
;------------------------------------------------------------------------------
print:
	push si
	mov si, ax
	mov ah, 0x0E

	.start_loop:
	mov al, [cs:si]
	test al, al
	jz .end_loop
	int 0x10
	inc si
	jmp .start_loop

	.end_loop:
	pop si
	ret

;------------------------------------------------------------------------------
; Function:		newline
; Description:	Print a newline ("\r\n").
;------------------------------------------------------------------------------
newline:
	mov ah, 0x0E
	mov al, 0xD ; '\r'
	int 0x10
	mov al, 0xA ; '\n'
	int 0x10
	ret

;------------------------------------------------------------------------------
; Function:		backspace
; Description:	Print a backspace ("\b \b").
;------------------------------------------------------------------------------
backspace:
	mov ah, 0x0E
	mov al, 8 ; '\b'
	int 0x10
	mov al, 0x20 ; ' '
	int 0x10
	mov al, 8 ; '\b'
	int 0x10
	ret

;------------------------------------------------------------------------------
; Function:		println
; Description:	Print a null-terminated string and a newline after it.
; 
; :param: str - Pointer to a null-terminates string.
; Note:			This function gets its input from the code segment, because
;				we print constants from our binary.
;------------------------------------------------------------------------------
println:
	call print
	call newline
	ret

;------------------------------------------------------------------------------
; Function:		memset
; Description:	Set memory to specified byte.
; 
; :param: buffer - Pointer to memory buffer.
; :param: byte - Byte value.
; :param: size - Length of the buffer (in bytes).
;
; Note:			The buffer segment is `es`.
;------------------------------------------------------------------------------
memset:
	push di
	mov di, ax
	mov al, bl
	repnz stosb ; I know this is not the most efficient way, but simplicity is important

	pop di
	ret

;------------------------------------------------------------------------------
; Function:		get_input
; Description:	Get input.
; 
; :param: buffer - Pointer to the memory buffer.
; :param: size - Maximum size of the buffer (including null-character).
; :return: 0 on success, 1 otherwise.
;------------------------------------------------------------------------------
get_input:
	enter 2,0
	push si

	mov [bp-2], ax ; buffer start
	mov si, ax ; buffer current position

	; if bx=0, return failure
	test bx, bx
	jz .fail
	dec bx ; leave one byte for null-character

	.start_loop:
	test bx, bx
	jz .only_enter_and_backspace

	xor ah, ah
	int 0x16 ; getchar

	; ignore if not ASCII
	test al, al
	jz .start_loop

	; if enter pressed, end loop
	cmp al, 0xD
	jz .end_loop

	; check for backspace
	cmp al, 8
	jz .backspace

	; normal character
	mov [si], al
	inc si
	dec bx
	mov ah, 0x0E
	int 0x10 ; print the character
	jmp .start_loop

	.backspace:
	; if we're in the start of the buffer, we can't backspace
	mov ax, [bp-2]
	cmp ax, si
	je .start_loop
	; print backspace, and delete the last character we got
	call backspace
	dec si
	mov [si], byte 0
	inc bx
	jmp .start_loop

	.only_enter_and_backspace:
	xor ah, ah
	int 0x16 ; getchar

	; if enter pressed, end loop
	cmp al, 0xD
	jz .end_loop

	; check for backspace
	cmp al, 8
	jz .backspace

	; otherwise, keep looking...
	jmp .only_enter_and_backspace

	.end_loop:
	mov [si], byte 0
	call newline
	xor ax, ax
	jmp .end

	.fail:
	mov ax, 1

	.end:
	pop si
	leave
	ret

;------------------------------------------------------------------------------
; Macro:		search_matching_bracket
; Description:	An inner macro for "emulate", search for matching and balanced
;				bracket.
; 
; :param: 1 - which bracket ('[' or ']')
;------------------------------------------------------------------------------
%macro search_matching_bracket 1
	; check jump condition
	mov al, [bx]
	test al, al
	%if %1 = '['
		jnz .start_loop
	%else 
		jz .start_loop
	%endif

	xor cx, cx ; holds the balance difference

	; we need to be in the "next" operation according to the direction,
	; so if we're going backward we need to make 2 backward steps
	%if %1 = ']'
		dec si
		dec si
	%endif

	%%start_loop:
	; if we're going backwards, we need to make sure that we don't underflow
	%if %1 = ']'
		mov ax, [bp-6] ; ax = start of program buffer
		cmp si, ax
		jb .fail_unbalanced_brackets
	%endif

	; read operation and move forward (or backward, of course)
	mov al, [si]
	%if %1 = '['
		inc si
	%else
		dec si
	%endif

	; compare to the same and matching bracket
	%if %1 = '['
		cmp al, '['
		jz %%found_same
		cmp al, ']'
		jz %%found_matching
	%else
		cmp al, ']'
		jz %%found_same
		cmp al, '['
		jz %%found_matching
	%endif

	; compare to null-byte (meaning we overflow)
	test al, al
	jz .fail_unbalanced_brackets

	; otherwise, keep searching
	jmp %%start_loop

	%%found_same:
	; we found the same bracket, so we need to increase the balance difference
	inc cx
	jmp %%start_loop

	%%found_matching:
	; we found matching bracket, check if we're baclanced or not
	test cx, cx
	jz %%end_loop
	; if we're not balanced, decrese balance difference and keep searching
	dec cx
	jmp %%start_loop

	%%end_loop:
	; we end up one operation "after" the matching bracket, which in the case of
	; left bracket it's the operation prior to the matching bracket, so we need 
	; to go forward 2 operations
	%if %1 = ']'
		inc si
		inc si
	%endif
	jmp .start_loop
%endmacro

;------------------------------------------------------------------------------
; Function:		emulate
; Description:	Emulate brainfuck code.
; 
; :param: program - Pointer to the program buffer (null-terminated string).
; :param: input - Pointer to the input buffer (null-terminated string).
; :param: data - Pointer to the data buffer.
; :param: size - Size of the data buffer.
; :return:
;
; Notes:
;------------------------------------------------------------------------------
emulate:
	enter 6,0
	push si
	push di

	; if data buffer size is 0, we already overflowed...
	test dx, dx
	jz .fail_data_overflow

	mov [bp-6], ax ; start of program buffer
	mov [bp-4], cx ; start of data buffer
	mov [bp-2], dx ; size of data buffer

	mov si, ax ; current program pointer
	mov di, bx ; current input pointer
	mov bx, cx ; current data pointer

	.start_loop:
	mov al, [si]
	inc si
	test al, al
	jz .end_loop

	; switch-case
	cmp al, '>'
	je .move_right
	cmp al, '<'
	je .move_left
	cmp al, '+'
	je .increment
	cmp al, '-'
	je .decrement
	cmp al, '.'
	je .output
	cmp al, ','
	je .input
	cmp al, '['
	je .left_bracket
	cmp al, ']'
	je .right_bracket

	; otherwise, ignore character
	jmp .start_loop

	.move_right:
	; check if we can move right
	mov ax, [bp-4]
	add ax, [bp-2] ; ax = start of data buffer + size of data buffer
	inc bx
	cmp bx, ax
	je .fail_data_overflow
	jmp .start_loop

	.move_left:
	; check if we can move left
	mov ax, [bp-4] ; ax = start of data buffer
	cmp bx, ax
	je .fail_data_underflow
	dec bx
	jmp .start_loop

	.increment:
	mov al, [bx]
	inc al
	mov [bx], al
	jmp .start_loop

	.decrement:
	mov al, [bx]
	dec al
	mov [bx], al
	jmp .start_loop

	.output:
	mov ah, 0x0E
	mov al, [bx]
	int 0x10
	jmp .start_loop

	.input:
	mov al, [di]
	inc di
	test al, al
	jz .fail_input_overflow
	mov [bx], al
	jmp .start_loop

	.left_bracket:
	search_matching_bracket '['

	.right_bracket:
	search_matching_bracket ']'

	.fail_data_overflow:
	call newline
	mov ax, emulate_data_overflow
	call println
	mov ax, 1
	jmp .end

	.fail_data_underflow:
	call newline
	mov ax, emulate_data_underflow
	call println
	mov ax, 2
	jmp .end

	.fail_input_overflow:
	call newline
	mov ax, emulate_input_overflow
	call println
	mov ax, 3
	jmp .end

	.fail_unbalanced_brackets:
	call newline
	mov ax, emulate_unbalanced_brackets
	call println
	mov ax, 4
	jmp .end

	.end_loop:
	xor ax, ax

	.end:
	pop di
	pop si
	leave
	ret

;------------------------------------------------------------------------------
; Strings
;------------------------------------------------------------------------------
welcome_msg db '------- RonHass brainfuck emulator -------', 0
enter_prog_msg db 'Program (16Kb max):', 0
enter_input_msg db 'Input (16Kb max):', 0
emulate_msg db 'Emulating program...', 0
emulate_end_msg db 'Emulation ended successfully! :)', 0
get_prog_fail_msg db 'Failed to get input program :(', 0
get_input_fail_msg db 'Failed to get input :(', 0
emulate_fail_msg db 'Failed to emulate program :(', 0
emulate_data_overflow db 'Error: data overflow', 0
emulate_data_underflow db 'Error: data underflow', 0
emulate_input_overflow db 'Error: input overflow', 0
emulate_unbalanced_brackets db 'Error: unbalenced brackets', 0
menu_msg db "Do you want to restart? ('s' for start over, 'r' for restart with the same program, any other character for exit)", 0
goodbye_msg db "See you next time!", 0