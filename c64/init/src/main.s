.CODE

main:
	; init stack pointer
	LDX #$FF
	TXS

	JSR init_basic

	LDX #<hello
	LDY #>hello
	JSR printstr
	; use BASIC-ROM to print ready
	LDA #>ready
	LDY #<ready
	JSR $AB1E
	; go on
	LDX #<ready
	LDY #>ready
l:
	JSR printstr
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

init_basic:
	LDA #$4C
	STA $54
	STA $0310
	LDA #$48   ; low  B248
	LDY #$B2   ; high B248
	STA $0311
	STY $0312
	LDA #$91   ; low B391
	LDY #$B3   ; high B391
	STA $05
	STY $06
	LDA #$AA   ; low  B1AA
	LDY #$B1   ; high B1AA
	STA $03
	STY $04
	LDX #$1C
init_basic_2:
	LDA $E3A2,X
	STA $73,X
	DEX
	BPL init_basic_2
	LDA #$03
	STA $53
	LDA #$00
	STA $68
	STA $13
	STA $18
	LDX #$01
	STX $01FD
	STX $01FC
	LDX #$19
	STX $16
	SEC
	JSR $FF9C
	STX $2B
	STY $2C
	SEC
	JSR $FF99
	STX $37
	STY $38
	STX $33
	STY $34
	LDY #$00
	TYA
	STA ($2B),Y
	INC $2B
	BNE init_basic_end
	INC $2C
init_basic_end:
	RTS

.DATA
hello: .asciiz "\n    **** commodore 64 basic v2 ****\n\n", " 64k ram system  ", "38911 basic bytes free\n"
ready: .asciiz "\nready.\n\n"
