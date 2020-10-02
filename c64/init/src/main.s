.CODE

printstr:
	; init stack pointer
	LDX #$FF
	TXS
	; init loop
	LDX #$00
printstr_loop:
	LDA hello,X
	JSR $FFD2 ; call CHROUT
	INX
	CMP #$00
	BNE printstr_loop
	RTS

.DATA
hello: .asciiz "\n    **** commodore 64 basic v2 ****\n\n", " 64k ram system  ", "38911 basic bytes free"
