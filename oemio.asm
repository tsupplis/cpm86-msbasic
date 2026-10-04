; OEMIO - operating system dependent primitives for a teletype style BASIC.
;
; The same source serves MS-DOS (INT 21h) and CP/M-86 (INT 224 BDOS): every
; call goes through CALLOS and only uses functions with identical numbers and
; register conventions on both systems.

	.RADIX	8		; To be safe

CSEG	SEGMENT PUBLIC 'CODESG'
	ASSUME	CS:CSEG

INCLUDE	OEM.INC

	TITLE	OEMIO - Console, printer and start-up primitives
	INCLUDE	MSDOSU.INC
	.SALL
	.RADIX	10

	BD_CONO=2D		;console output (DL)
	BD_LSTO=5D		;list output (DL)
	BD_DCIO=6D		;direct console I/O (DL=255: input, AL=0 if none)
	BD_RDKY=7D		;DOS: console input without echo

	PUBLIC	CONOUT,CONKEY,CONPOL,LSTOUT

SAVALL	MACRO
	PUSH	BX
	PUSH	CX
	PUSH	DX
	PUSH	SI
	PUSH	DI
	PUSH	BP
	PUSH	ES
ENDM

RESALL	MACRO
	POP	ES
	POP	BP
	POP	DI
	POP	SI
	POP	DX
	POP	CX
	POP	BX
ENDM

;CONOUT - write the byte in [AL] to the console.  All registers preserved.
;
CONOUT:	PUSH	AX
	SAVALL
	MOV	DL,AL
	CALLOS	BD_CONO
	RESALL
	POP	AX
	RET	

;CONPOL - look for a key without waiting.
; Exit  - PSW.Z set if no key, else PSW.Z reset and [AL] = key (consumed).
;         All other registers preserved.
;
CONPOL:	SAVALL
	MOV	DL,LOW 255D
	CALLOS	BD_DCIO
	OR	AL,AL
	PUSHF	
	POPF	
	RESALL
	RET	

;CONKEY - wait for a key and return it in [AL] (no echo).  Other registers
; preserved.
;
CONKEY:
IF	CPM86
CONKY1:	CALL	CONPOL
	JZ	CONKY1
	RET	
ELSE
	SAVALL
CONKY1:	CALLOS	BD_RDKY
	OR	AL,AL
	JNZ	CONKY2
	CALLOS	BD_RDKY		;extended key: discard the scan code
	JMP	SHORT CONKY1
CONKY2:	RESALL
	RET	
ENDIF

;LSTOUT - write the byte in [AL] to the printer.  All registers preserved.
;
LSTOUT:	PUSH	AX
	SAVALL
	MOV	DL,AL
	CALLOS	BD_LSTO
	RESALL
	POP	AX
	RET	


IF	DEBUG
;DBGERR - (DEBUG builds) show "[E dl=xx a=xxxx b=xxxx]" when ERROR is entered:
; the error code and the two words on top of the stack.  All registers kept.
;
	PUBLIC	DBGERR,DBGCH,DBGHEX
DBGCH:	JMP	CONOUT

DBGERR:	PUSH	BP
	MOV	BP,SP
	PUSHF	
	PUSH	AX
	MOV	AL,LOW "["
	CALL	CONOUT
	MOV	AL,LOW "E"
	CALL	CONOUT
	MOV	AL,DL
	CALL	DBGH8
	MOV	AX,WORD PTR 4[BP]
	CALL	DBGH16
	MOV	AX,WORD PTR 6[BP]
	CALL	DBGH16
	MOV	AX,WORD PTR 8[BP]
	CALL	DBGH16
	MOV	AL,LOW "]"
	CALL	CONOUT
	POP	AX
	POPF	
	POP	BP
	RET	

DBGBXR:	PUSHF	
	PUSH	AX
	PUSH	BX
	MOV	AL,LOW "<"
	CALL	CONOUT
	MOV	AX,BX
	CALL	DBGH16
	MOV	AL,BYTE PTR -1[BX]
	CALL	DBGSP8
	MOV	AL,BYTE PTR 0[BX]
	CALL	DBGSP8
	MOV	AL,BYTE PTR 1[BX]
	CALL	DBGSP8
	MOV	AL,BYTE PTR 2[BX]
	CALL	DBGSP8
	MOV	AL,LOW ">"
	CALL	CONOUT
	POP	BX
	POP	AX
	POPF	
	RET	

DBGSP8:	PUSH	AX
	MOV	AL,LOW " "
	CALL	CONOUT
	POP	AX
	JMP	DBGH8

;DBGHEX - (DEBUG) show [AX] as " xxxx" on the console.  Registers kept.
DBGHEX:	PUSHF	
	PUSH	AX
	CALL	DBGH16
	POP	AX
	POPF	
	RET	

DBGH16:	PUSH	AX
	MOV	AL,LOW " "
	CALL	CONOUT
	POP	AX
	PUSH	AX
	MOV	AL,AH
	CALL	DBGH8
	POP	AX
DBGH8:	PUSH	AX
	PUSH	CX
	MOV	CL,LOW 4
	SHR	AL,CL
	CALL	DBGH4
	POP	CX
	POP	AX
DBGH4:	AND	AL,LOW 15D
	ADD	AL,LOW "0"
	CMP	AL,LOW "9"
	JBE	DBGH5
	ADD	AL,LOW 7D
DBGH5:	JMP	CONOUT
ENDIF

CSEG	ENDS
	END
