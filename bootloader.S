;------------------------------------------------------------------------------
; File:			bootloader.S
; Description:	The first code which runs after the BIOS, has 3 main
;				responsibilities:
;				1. Load the payload (which resides in the next sectors).
;				2. Initialize the stack.
;				3. Call the main function in the payload (which resides in the
;				   start of the payload).
;
; Notes:		We assume the bootloader starts at address 0x7C00, and all the
;				segments (CS,DS,ES,SS) are set to zero.
;				Therefore, the payload will be loaded at address 0x7E00, and we 
;				initialize the stack at address 0x1FFFC (for the largest stack 
;				possible). We do so by setting DS = ES = SS = 0x1000 (while CS 
;				remains zero).
;
;				For example, if the payload length is 2 sectors, the memory 
;				layout will be:
;				0x07C00 - 0x07DFF - our booloader
;				0x07E00 - 0x081FF - payload
;				0x08200 - 0x0FFFF - unused
;				0x10000 - 0x1FFFC - stack
;
;				Because the code must remain in the code segment bounds, the 
;				maximum length of the payload is 65 sectors (32.5Kb).
;------------------------------------------------------------------------------

[BITS 16]
global _start

; Number of retries to load the code from the disk
%define NUM_OF_RETRIES 5
; Number of sectors to load
%define NUM_OF_SECTORS 65

;------------------------------------------------------------------------------
; Macro:		print_inline
; Description:	Print a null-terminated string using BIOS interrupts.
; 
; :param: 1 - null-terminated string
;
; Notes:		Changes ax, si registers.
;				This macro gets its input from the code segment, because
;				we print constants from our binary.
;------------------------------------------------------------------------------
%macro print_inline 1
	mov si, %1
	mov ah, 0x0E

	%%start_loop:
	mov al, [cs:si]
	test al, al
	jz %%end_loop
	int 0x10
	inc si
	jmp %%start_loop

	%%end_loop:
%endmacro

;------------------------------------------------------------------------------
; Code section
;------------------------------------------------------------------------------
section .text

_start:
	print_inline welcome_msg

	; validating CS,DS,ES,SS segments are all set to 0
	mov ax, cs
	test ax, ax
	jnz .invalid_segment
	mov ax, ds
	test ax, ax
	jnz .invalid_segment
	mov ax, cs
	test ax, ax
	jnz .invalid_segment
	mov ax, ss
	test ax, ax
	jnz .invalid_segment

	; loading next sectors
	mov di, NUM_OF_RETRIES ; number of retries
	xor ch, ch ; cylinder number 0
	xor dh, dh ; head number 0
	mov cl, 2 ; sector number 2 (1-based, so the second sector)
	xor dl, dl ; load from floppy disk
	mov bx, main ; offset to the buffer in the segment

.load_sectors:
	mov al, NUM_OF_SECTORS ; number of sectors
	mov ah, 0x02 ; BIOS function code
	clc ; clear carry flag
	int 0x13
	jnc .success_load

	; check for number of retries
	dec di
	test di, di
	jnz .load_sectors

	; failure
	print_inline failure_msg
	jmp .hang

.success_load:
	print_inline success_msg

	; initalizing stack to address 0x1FFFC (dword-alignment)
	mov ax, 0x1000
	mov ss, ax ; SS = 0x1000
	mov ds, ax ; DS = 0x1000
	mov es, ax ; ES = 0x1000
	mov sp, 0xFFFC ; SP = 0x777C
	mov bp, sp

	; jump to the main function
	jmp main

.invalid_segment:
	print_inline invalid_segments_msg
.hang:
	jmp $

;------------------------------------------------------------------------------
; Strings
;------------------------------------------------------------------------------
welcome_msg db '------- RonHass bootloader -------', 13, 10, 0
success_msg db 'Loaded payload successfully :)', 13, 10, 0
failure_msg db 'Failed to load payload :(', 13, 10, 0
invalid_segments_msg db 'Invalid segments! :(', 13, 10, 0

;------------------------------------------------------------------------------
; Bootloader magic
;------------------------------------------------------------------------------
times 510-($-$$) db 0
db 0x55, 0xAA

;------------------------------------------------------------------------------
; Next sectors
;------------------------------------------------------------------------------
main:
