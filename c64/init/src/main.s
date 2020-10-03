.CODE

main:
	; init stack pointer
	LDX #$FF
	TXS

	LDX #<hello
	LDY #>hello
	JSR printstr

	LDX #<ready
	LDY #>ready
	JSR printstr
l:
	JSR input
	JSR skip_line
	JMP l
	BRK

input:
	; loop while a != CR
	JSR $FFCF ; call CHRIN
	CMP #$0D
	BEQ input_end
	JSR $FFD2 ; print the inputed character
	JMP input
input_end:
	RTS

skip_line:
	SEC
	JSR $FFF0 ; call PLOT to get cursor position
	LDY #$00 ; reset x position
	INX ; y position + 1
	CLC
	JSR $FFF0 ; set cursor position
	RTS

printstr:
	; init loop
	STX $17
	STY $18
	LDY #$00
printstr_loop:
	LDA ($17),Y
	INY
	CMP #$00
	BEQ printstr_end
	JSR $FFD2 ; call CHROUT
	JMP printstr_loop
printstr_end:
	RTS

.DATA
hello: .asciiz "\n    **** commodore 64 basic v2 ****\n\n", " 64k ram system  ", "38911 basic bytes free"
ready: .asciiz "\n\nready.\n\n"
