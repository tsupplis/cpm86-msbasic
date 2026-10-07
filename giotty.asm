; GIOTTY - teletype console for BASIC-86: the KYBD: and SCRN: devices, line
;          input, INKEY$ and CTL-C handling.
;
; This replaces the GW-BASIC screen driver, screen editor and keyboard driver.
; Only three operating system primitives are used (see OEMIO): CONOUT,
; CONPOL and CONKEY.

	.RADIX	8		; To be safe

CSEG	SEGMENT BYTE PUBLIC 'CODESG'
	ASSUME	CS:CSEG

INCLUDE	OEM.INC

	TITLE	GIOTTY - Teletype console device driver
	INCLUDE	GIO86U.INC
	INCLUDE	MSDOSU.INC
	.SALL
	.RADIX	10

	PUBLIC	KYBDSP,KYBINI,KYBTRM,SCNDSP,SCNINI,SCNTRM
	PUBLIC	CALTTY,$CATTY,POS,KYBSIN,INCHRI,POLKEY,INKEY
	PUBLIC	PINLIN,QINLIN,INLIN,SINLIN,SCNSEM,ERREDT,EDIT,OUTCH1,GETWID

	EXTRN	DERBFM:NEAR,INIFDB:NEAR,DEVBIN:NEAR,DEVBOT:NEAR
	EXTRN	OUTDO:NEAR,CRDO:NEAR,CHRGTR:NEAR,MAKINT:NEAR,SNGFLT:NEAR
	EXTRN	GETBYT:NEAR,FCERR:NEAR,SNERR:NEAR,STOP:NEAR,FINPRT:NEAR
	EXTRN	INITQ:NEAR,GETQ:NEAR,PUTQ:NEAR,NUMQ:NEAR,LFTQ:NEAR
	EXTRN	INCHSI:NEAR,BCHRSI:NEAR,ISFLIO:NEAR,INCHR:NEAR,LBOERR:NEAR
	EXTRN	STRIN1:NEAR,SETSTR:NEAR,PUTNEW:NEAR
	EXTRN	CONOUT:NEAR,CONPOL:NEAR,CONKEY:NEAR
	EXTRN	LINSPC:NEAR,FNDLIN:NEAR,LINPRT:NEAR,BUFLIN:NEAR,EDENT:NEAR
	EXTRN	READY:NEAR,USERR:NEAR,MAIN:NEAR

DSEG	SEGMENT PUBLIC 'DATASG'
	ASSUME DS:DSEG
	EXTRN	BUF:WORD,SEMFLG:WORD
	EXTRN	AUTFLG:WORD,TTYPOS:WORD,LINLEN:WORD,WDTFLG:WORD,MSDCCF:WORD
	EXTRN	PTRFIL:WORD,SAVSTK:WORD,SAVTXT:WORD,CURLIN:WORD,FILMOD:WORD
	EXTRN	KYBQDS:WORD,KYBQUE:WORD,KYBQSZ:WORD
	EXTRN	DSCPTR:WORD,VALTYP:WORD,FACLO:WORD,DSEGZ:WORD
	EXTRN	EDTFLG:WORD,EDTLIN:WORD,EDTPOS:WORD,EDTLEN:WORD
	EXTRN	DOT:WORD,ERRLIN:WORD,ERRFLG:WORD,AUTLIN:WORD,INLBEG:WORD
	EXTRN	INMAIN:WORD,INLSP:WORD,RUBFLG:WORD,CNTOFL:WORD
DSEG	ENDS

	CHRBKW=8D		;backspace
	CHRTAB=9D		;tab
	CHRLNF=10D		;line feed
	CHRRET=13D		;carriage return
	CHRCAN=21D		;CTL-U cancels the line
	CHRHCN=24D		;CTL-X cancels the line
	CHRDEL=127D		;rubout
	CHRBRK=3D		;CTL-C
	CHRESC=27D		;ESC
	CHRBEL=7D		;bell
	CHRCTO=15D		;CTL-O suppresses output
	CHRRTY=18D		;CTL-R retypes the line
	CHRPAS=19D		;CTL-S
	MAXLIN=254D		;longest line that fits in BUF

;Screen Dispatch Table
;
SCNDSP:
	DW	(DERBFM)	;test EOF for file opened to this device
	DW	(DERBFM)	;LOC
	DW	(DERBFM)	;LOF
	DW	(SCNCLS)	;perform special CLOSE functions for this device
	DW	(SCNSWD)	;set device width
	DW	(DERBFM)	;GET/PUT random record from/to this device
	DW	(SCNOPN)	;perform special OPEN functions for this device
	DW	(DERBFM)	;input 1 byte from file opened on this device
	DW	(SCNSOT)	;output 1 byte to file opened on this device
	DW	(SCNGPS)	;POS
	DW	(SCNGWD)	;get device width
	DW	(SCNSCW)	;set device comma width
	DW	(SCNGCW)	;get device comma width
	DW	(DEVBIN)	;block input from file opened on this device
	DW	(DEVBOT)	;block output to file opened on this device

;Keyboard Dispatch Table
;
KYBDSP:
	DW	(KYBEOF)	;test EOF for file opened to this device
	DW	(KYBLOC)	;LOC
	DW	(KYBLOF)	;LOF
	DW	(KYBCLS)	;perform special CLOSE functions for this device
	DW	(SCNSWD)	;set device width
	DW	(DERBFM)	;GET/PUT random record from/to this device
	DW	(KYBOPN)	;perform special OPEN functions for this device
	DW	(KYBSIN)	;input 1 byte from file opened on this device
	DW	(SCNSOT)	;output 1 byte to file opened on this device
	DW	(SCNGPS)	;POS
	DW	(SCNGWD)	;get device width
	DW	(SCNSCW)	;set device comma width
	DW	(SCNGCW)	;get device comma width
	DW	(DEVBIN)	;block input from file opened on this device
	DW	(DEVBOT)	;block output to file opened on this device

	PAGE	
	SUBTTL	SCRN: device

;SCNINI is called to initialize the console when BASIC comes up
;
SCNINI:	MOV	BYTE PTR LINLEN,LOW 80D	;default console width
	MOV	BYTE PTR WDTFLG,LOW 80D
	MOV	BYTE PTR TTYPOS,LOW 1D
	RET	

SCNTRM:
SCNCLS:	RET	

;SCNSWD - set device width
; Entry - [DL] = new device width
;
SCNSWD:	MOV	BYTE PTR WDTFLG,DL
	MOV	BYTE PTR LINLEN,DL
	RET	

;SCNOPN - open SCRN: (output only)
; Exit  - [SI] points to the new FDB
;
SCNOPN:	CALL	SCNGPS		;[AH]=current column position (0-relative)
	MOV	DH,AH		;[DH]=current column position
	MOV	AH,LOW OFFSET MD_SQO	;allow open for output only
	MOV	DL,BYTE PTR WDTFLG	;initial file logical width
	JMP	INIFDB

;CALTTY outputs an error message to the console regardless of the current
; file I/O.
; Entry - [AL] = byte to be output.  All registers preserved.
;
$CATTY:
CALTTY:	PUSH	WORD PTR PTRFIL
	MOV	WORD PTR PTRFIL,0	;Make sure we go to the "TTY"
	CALL	OUTDO
	POP	WORD PTR PTRFIL
	RET	

;SCNSOT - Sequential Output.
; Entry - [AL] = byte to be output.  SI is 0 or points to a file data block.
; Exit  - SI, DI can be changed.  All other registers preserved.
;         Wrapping at the right margin is done by the caller (OUTDO).
;
SCNSOT:	TEST	BYTE PTR CNTOFL,LOW 255D
	JZ	SCNSO0
	RET			;output suppressed by CTL-O
SCNSO0:	PUSHF	
	PUSH	AX
	CMP	AL,LOW OFFSET CHRTAB
	JNE	SCNOT1
SCNTB1:	MOV	AL,LOW " "		;expand tabs to 8 column stops
	CALL	SCNPUT
	MOV	AL,BYTE PTR TTYPOS
	DEC	AL
	TEST	AL,LOW 7D
	JNZ	SCNTB1
	JMP	SHORT SCNOTX
SCNOT1:	CALL	SCNPUT
SCNOTX:	POP	AX
	POPF	
	RET	

;SCNPUT - send [AL] to the console, forcing a new line first when the right
; margin (file width, or the console width) has been reached.
;
SCNPUT:	CMP	AL,LOW " "
	JB	SCNRAW		;control characters never wrap
	PUSH	DX
	MOV	DL,BYTE PTR LINLEN
	OR	SI,SI
	JZ	SCNPW1		;not file I/O: use the console width
	MOV	DL,BYTE PTR F_WID[SI]
SCNPW1:	CMP	DL,LOW 255D
	JE	SCNPW2		;255 = infinite width
	MOV	DH,BYTE PTR TTYPOS
	DEC	DH		;0-relative column
	CMP	DH,DL
	JB	SCNPW2		;still room on this line
	PUSH	AX
	MOV	AL,LOW OFFSET CHRRET
	CALL	SCNRAW
	MOV	AL,LOW OFFSET CHRLNF
	CALL	SCNRAW
	POP	AX
SCNPW2:	POP	DX

;SCNRAW - send [AL] to the console and update the column
;
SCNRAW:	CALL	CONOUT
	CMP	AL,LOW OFFSET CHRRET
	JE	SCNCR
	CMP	AL,LOW OFFSET CHRBKW
	JE	SCNBS
	CMP	AL,LOW " "
	JB	SCNPTX		;other control characters do not move the cursor
	CMP	BYTE PTR TTYPOS,LOW 255D
	JE	SCNPTX
	INC	BYTE PTR TTYPOS
	RET	
SCNCR:	MOV	BYTE PTR TTYPOS,LOW 1D
	RET	
SCNBS:	CMP	BYTE PTR TTYPOS,LOW 1D
	JBE	SCNPTX
	DEC	BYTE PTR TTYPOS
SCNPTX:	RET	

;POS(X) function
;
POS:	MOV	AL,BYTE PTR TTYPOS	;[AL]=current 1 relative position
	CMP	AL,BYTE PTR LINLEN
	JBE	POS0		;BRIF not beyond end of line
	MOV	AL,LOW 1	;Else next char will go in first column
POS0:	JMP	SNGFLT		;return result to user

;SCNGPS - return current file position.
; Exit  - [AH] = current column (0-relative).  Other registers preserved.
;
SCNGPS:	MOV	AH,BYTE PTR TTYPOS
	PUSHF	
	CMP	AH,BYTE PTR LINLEN
	JBE	SCNGP1		;BRIF not beyond edge of screen
	MOV	AH,BYTE PTR LINLEN	;Force posn within screen
SCNGP1:	POPF	
	DEC	AH		;Make it 0 relative
	RET	

;SCNGWD - get device width
; Exit  - [AH] = device width.  Other registers preserved.
;
SCNGWD:	MOV	AH,BYTE PTR LINLEN
	OR	SI,SI
	JZ	SCNGWX		;BRIF not file I/O, use device width
	MOV	AH,BYTE PTR F_WID[SI]	;Is file I/O, use FDB width
SCNGWX:	RET	

;SCNSCW/SCNGCW - comma width is not changeable
;
SCNSCW:
SCNGCW:	RET	

;GETWID - evaluate a width: 1..255.  Entered like GWWID.
;
GETWID:	DEC	BX
	CALL	CHRGTR
	CALL	GETBYT
	OR	AL,AL
	JZ	GETWDE
	RET	
GETWDE:	JMP	FCERR

	PAGE	
	SUBTTL	KYBD: device

;KYBINI puts the keyboard device server in an initial state.  It is called at
; initialization time and after CTL-C.  All registers preserved.
;
KYBINI:	PUSH	AX
	PUSH	BX
	PUSH	SI
	PUSHF	
	MOV	SI,OFFSET KYBQDS	;SI = keyboard queue descriptor
	MOV	BX,OFFSET KYBQUE	;BX points to 1st byte of queue buff
	MOV	AX,OFFSET KYBQSZ	;AX = size of keyboard queue
	CALL	INITQ
	POPF	
	POP	SI
	POP	BX
	POP	AX
	JMP	FINPRT		;reset PTRFIL to the console

KYBTRM:
KYBCLS:	RET	

;KYBEOF - test for End-Of-File.  [BX] = -1 if EOF, else 0.
;
KYBEOF:	XOR	BX,BX		;0 means not at eof
	OR	SI,SI
	JZ	KBEOFX		;branch if not pseudo keyboard FDB
	CALL	INCHSI		;[AL]=next byte from keyboard
	JB	YKYEOF		;branch if next key = CTL-Z
	CALL	BCHRSI		;put this back in queue
KBEOFX:	RET	
YKYEOF:	DEC	BX		;BX=-1, end-of-file is true
	RET	

;KYBLOC - number of bytes waiting
;
KYBLOC:	PUSH	SI
	MOV	SI,OFFSET KYBQDS
	CALL	NUMQ
	POP	SI
	MOV	BX,AX
	TEST	BYTE PTR F_FLGS[SI],LOW OFFSET FL_BKC
	JZ	KYLOCX		;branch if char not backed up
	INC	BX
KYLOCX:	RET	

;KYBLOF - free space in the type-ahead buffer
;
KYBLOF:	MOV	SI,OFFSET KYBQDS
	CALL	LFTQ
	MOV	BX,AX
	JMP	MAKINT		;return result in FAC

;KYBOPN - open KYBD: (input only)
;
KYBOPN:	MOV	AH,LOW OFFSET MD_SQI	;allow input only
	CMP	BYTE PTR FILMOD,LOW OFFSET MD_RND
	JNZ	KYBOPX		;Leave the mode as it is
	MOV	BYTE PTR FILMOD,AH	;Force the mode to INPUT
KYBOPX:	JMP	INIFDB

;KYBSIN - sequential input.
; Exit  - [AL] = next byte.  Carry set if CTL-Z was read and SI points to an
;         FDB.  All other registers preserved.
;
KYBSIN:	CALL	KEYIN
	OR	SI,SI
	JZ	KBSIN1		;branch if no FDB
	CMP	AL,LOW OFFSET ASCCTZ	;CTL-Z=eof for keyboard
	JNE	KBSIN1
	STC	
	RET	
KBSIN1:	CLC	
	RET	

;INCHRI - fixed length input (INPUT$): next key, no EOF test
;
INCHRI:	JMP	KEYIN

;CHSNS - get a key if one is ready.
; Exit  - PSW.Z set if no key, else [AL] = key.  All other registers preserved.
;
CHSNS:	PUSH	BX
	PUSH	SI
	MOV	SI,OFFSET KYBQDS
	CALL	GETQ		;AX is used
	POP	SI
	POP	BX
	JNZ	CHSNSX		;got a queued key
	CALL	CONPOL
	JZ	CHSNSX		;no key typed
	CALL	CTLCHK		;CTL-C does not return
	OR	AL,AL		;NZ
CHSNSX:	RET	

;KEYIN - wait for a key.  Exit - [AL] = key.  Other registers preserved.
;
KEYIN:	CALL	CHSNS
	JNZ	KEYINX
	CALL	CONKEY
	CALL	CTLCHK		;CTL-C does not return
KEYINX:	RET	

;CTLCHK - a CTL-C typed (or signalled by the operating system) breaks the
; program.
;
CTLCHK:	CMP	AL,LOW OFFSET CHRBRK
	JE	ITSCTC
	TEST	BYTE PTR MSDCCF,LOW 255D
	JNZ	ITSCTC
	RET	
ITSCTC:	MOV	BYTE PTR MSDCCF,LOW 0D	;Reset Ctl-Break interrupt flag
	CALL	KYBINI		;clear keyboard queue, reset PTRFIL
	MOV	AL,LOW "^"
	CALL	OUTDO
	MOV	AL,LOW "C"
	CALL	OUTDO
	CALL	CRDO
	TEST	BYTE PTR INMAIN,LOW 255D
	JZ	CTLBRK		;not at the command prompt
	CALL	CLRFLG
	MOV	SP,WORD PTR INLSP
	POP	AX		;PINLIN's return address
	TEST	BYTE PTR AUTFLG,LOW 255D
	MOV	BYTE PTR AUTFLG,LOW 0D
	JZ	CTLMN
	JMP	READY		;AUTO ends with "Ok"
CTLMN:	JMP	MAIN		;otherwise just a new input line
CTLBRK:	CALL	CLRFLG
	MOV	SP,WORD PTR SAVSTK	;[SP]=SP of interrupted statement
	MOV	BX,WORD PTR SAVTXT	;[BX]=text pointer of interrupted stmt
	MOV	BYTE PTR AUTFLG,LOW 0D	;leave AUTO mode
	MOV	AX,WORD PTR CURLIN	;Print "BREAK" message in program mode only
	AND	AL,AH		;AL=^D255 if direct mode
	XOR	AH,AH		;Set PSW.Z so STOP won't give Syntax Error
	CALL	STOP		;CALL: STOP discards a statement return address

;POLKEY is called from several places in BASIC to poll the keyboard.
; Exit - DI is used.  All other registers preserved.  If CTL-C was typed,
;        control does not return to the caller.  CTL-S pauses.  Other keys
;        are queued for INKEY$ and INPUT.
;
POLKEY:	PUSH	DI
	PUSHF	
	PUSH	AX
	PUSH	BX
	PUSH	SI
	TEST	BYTE PTR MSDCCF,LOW 255D
	JZ	POLKLP
	MOV	AL,LOW OFFSET CHRBRK
	CALL	CTLCHK
POLKLP:	CALL	CONPOL
	JZ	POLKXI		;no more keys
	CMP	AL,LOW OFFSET CHRBRK
	JE	POLKBK
	CMP	AL,LOW OFFSET CHRPAS
	JE	POLKPS
	MOV	SI,OFFSET KYBQDS
	CALL	PUTQ
	JMP	SHORT POLKLP
POLKPS:	CALL	CONKEY		;wait for any key to resume
	CMP	AL,LOW OFFSET CHRBRK
	JNE	POLKLP
POLKBK:	CALL	CTLCHK
POLKXI:	POP	SI
	POP	BX
	POP	AX
	POPF	
	POP	DI
	RET	

;INKEY$ - get key if one is ready, else return the null string.
;
INKEY:	CALL	CHRGTR
	PUSH	BX		;save text pointer
	CALL	CHSNS
	JZ	NULRT		;branch if no key is ready
	PUSH	AX
	CALL	STRIN1		;MAKE ONE CHAR STRING
	POP	AX
	MOV	DL,AL
	CALL	SETSTR		;STUFF IN DESCRIPTOR AND GOTO PUTNEW
NULRT:	MOV	BX,OFFSET DSEGZ	;GUARANTEED ZERO IN DATA SEGMENT
	MOV	WORD PTR FACLO,BX
	MOV	BYTE PTR VALTYP,LOW 3
	POP	BX		;restore text pointer
	RET	

	PAGE	
	SUBTTL	Line input

;PROGRAM STATEMENT INPUT
;
PINLIN:	CALL	DSKCHI		; Don't return if Loading ASCII File
	MOV	WORD PTR INLSP,SP
	MOV	BYTE PTR INMAIN,LOW 1
	TEST	BYTE PTR EDTFLG,LOW 255D
	JZ	PINLN1
	JMP	EDLINE		;EDIT (or automatic edit) was requested
PINLN1:	MOV	DI,OFFSET BUF
	TEST	BYTE PTR AUTFLG,LOW 255D
	JZ	INLIN1
;AUTO: MAIN has shown "nnn" and " " or "*"; put the same in BUF so the line
; is entered with its number.
	MOV	AX,WORD PTR AUTLIN
	CALL	DECOUT		;digits at [DI]
	MOV	AL,BYTE PTR AUTFLG
	STOSB			;" ", or "*" if the line exists
	JMP	SHORT INLIN1
	STC			; Indicate program statement input
	JMP	SHORT INLIN0

;PRINT "?" BEFORE GETTING INPUT
;
QINLIN:	MOV	AL,LOW "?"
	CALL	OUTDO
	MOV	AL,LOW " "
	CALL	OUTDO

;INPUT STATEMENT (and INPUT redo)
;
INLIN:
SINLIN:
INLIN0:
	MOV	DI,OFFSET BUF	;DI = next free byte of BUF
INLIN1:	MOV	WORD PTR INLBEG,DI
	XOR	CX,CX		;CX = characters typed
INLLOP:	CALL	KEYIN
	CMP	AL,LOW OFFSET CHRDEL
	JE	INLRUB
	CALL	RUBEND		;any other key closes a \...\ display
	CMP	AL,LOW OFFSET CHRRET
	JNE	INLLP1
	JMP	INLRET
INLLP1:	CMP	AL,LOW OFFSET CHRBKW
	JE	INLBS
	CMP	AL,LOW OFFSET CHRCAN
	JE	INLCAN
	CMP	AL,LOW OFFSET CHRHCN
	JE	INLCNX
	CMP	AL,LOW OFFSET CHRRTY
	JE	INLRTY
	CMP	AL,LOW OFFSET CHRLNF
	JE	INLLF
	CMP	AL,LOW OFFSET CHRCTO
	JNE	INLLP2
	JMP	INLCTO
INLLP2:
	CMP	AL,LOW OFFSET CHRTAB
	JE	INLCHR
	CMP	AL,LOW OFFSET CHRBEL
	JE	INLCHR
	CMP	AL,LOW " "
	JB	INLLPJ		;ignore other control characters
INLCHR:	CALL	INLPUT
	JB	INLLPJ		;line full
	CALL	OUTDO
INLLPJ:	JMP	INLLOP

;LF is kept in the line; the echo moves to a new physical line
INLLF:	CALL	INLPUT
	JB	INLLPJ
	CALL	OUTDO
	MOV	AL,LOW OFFSET CHRRET
	CALL	OUTDO
	JMP	INLLOP

;rubout (DEL): show the deleted characters between backslashes
INLRUB:	JCXZ	INLLPJ		;nothing to rub out
	TEST	BYTE PTR RUBFLG,LOW 255D
	JNZ	INLRB1
	MOV	BYTE PTR RUBFLG,LOW 1
	MOV	AL,LOW "\"
	CALL	OUTDO
INLRB1:	DEC	DI
	DEC	CX
	MOV	AL,BYTE PTR 0[DI]
	CALL	OUTDO
	JMP	INLLOP

;backspace: erase the last character on the screen
INLBS:	JCXZ	INLLPJ		;nothing to rub out
	DEC	DI
	DEC	CX
	MOV	AL,LOW OFFSET CHRBKW
	CALL	OUTDO
	MOV	AL,LOW " "
	CALL	OUTDO
	MOV	AL,LOW OFFSET CHRBKW
	CALL	OUTDO
	JMP	INLLOP

;CTL-U: "^U", CTL-X: "#"; the line is abandoned
INLCAN:	MOV	AL,LOW "^"
	CALL	OUTDO
	MOV	AL,LOW "U"
	JMP	SHORT INLCN1
INLCNX:	MOV	AL,LOW "#"
INLCN1:	CALL	OUTDO
	CALL	CRDO
	MOV	DI,WORD PTR INLBEG
	XOR	CX,CX
	JMP	INLLOP

;CTL-R: show the line again on a new line
INLRTY:	CALL	CRDO
	MOV	SI,OFFSET BUF
INLRT1:	CMP	SI,DI
	JAE	INLRT2
	MOV	AL,BYTE PTR 0[SI]
	CALL	OUTDO
	INC	SI
	JMP	SHORT INLRT1
INLRT2:	JMP	INLLOP

;CTL-O: "^O", then output is suppressed until the next "Ok"
INLCTO:	MOV	AL,LOW "^"
	CALL	OUTDO
	MOV	AL,LOW "O"
	CALL	OUTDO
	XOR	BYTE PTR CNTOFL,LOW 1
	JMP	INLLOP

;INLPUT - store [AL] in the line.  PSW.C if the line is full.
;
INLPUT:	CMP	CX,MAXLIN
	CMC	
	JB	INLPTX
	MOV	BYTE PTR 0[DI],AL
	INC	DI
	INC	CX
	CLC	
INLPTX:	RET	

;RUBEND - close an open \...\ rubout display.  All registers kept.
;
RUBEND:	TEST	BYTE PTR RUBFLG,LOW 255D
	JZ	RUBENX
	MOV	BYTE PTR RUBFLG,LOW 0
	PUSH	AX
	MOV	AL,LOW "\"
	CALL	OUTDO
	POP	AX
RUBENX:	RET	

INLRET:	MOV	BYTE PTR 0[DI],LOW 0D	;Terminate BUF
	TEST	BYTE PTR SEMFLG,LOW 377O
	JNZ	INLFIN		;BRIF INPUT; statement: no new line
	CALL	CRDO
INLFIN:	CALL	CLRFLG		;Clear miscellaneous status flags
	MOV	BX,OFFSET BUF-1	;Return BUF - 1
	CLC	
	RET	

CLRFLG:	MOV	BYTE PTR SEMFLG,LOW 0	; Not INPUT; statement
	MOV	BYTE PTR INMAIN,LOW 0
	RET	

;SCAN FOR SEMICOLON
;
SCNSEM:	CMP	AL,LOW ";"
	JNZ	SCNSMR		; BRIF not semicolon, return
	MOV	BYTE PTR SEMFLG,AL
	JMP	CHRGTR		; Skip semicolon and return
SCNSMR:	RET	

;EDIT line - request the line editor.  The editor runs from PINLIN on the
; next program line input, so that its result is entered like a typed line.
;
EDIT:	CALL	LINSPC		;[DX]=line number ("." allowed)
	JZ	EDIT1
	JMP	SNERR		;statement must end here
EDIT1:	MOV	WORD PTR DOT,DX
	CALL	FNDLIN
	JB	EDIT2
	JMP	USERR		;"Undefined line number"
EDIT2:	MOV	WORD PTR EDTLIN,DX
	MOV	BYTE PTR EDTFLG,LOW 1
	POP	AX		;drop the NEWSTT return address
	JMP	MAIN

;ERREDT - called by READY after a syntax error: edit the faulty program line.
; Entry - [AL]=0
;
ERREDT:	MOV	BYTE PTR ERRFLG,AL	;don't do it again
	MOV	DX,WORD PTR ERRLIN
	CMP	DX,0FFFFH
	JE	ERRED1		;direct statement: nothing to edit
	OR	DX,DX
	JZ	ERRED1
	MOV	WORD PTR EDTLIN,DX
	MOV	BYTE PTR EDTFLG,LOW 1
ERRED1:	RET	

	PAGE	
	SUBTTL	EDIT mode (MBASIC line editor)

;Sub-commands ([n] is an optional repeat count):
;  [n]space   move right, showing the characters
;  [n]rubout  move left (backspace or DEL)
;  [n]D       delete, showing \deleted\
;  [n]C       change the next n characters to the keys typed
;  [n]Sc      move to the n-th c to the right
;  [n]Kc      delete up to the n-th c to the right, showing \deleted\
;  I          insert until ESC (or CR, which ends the edit)
;  X          go to the end of the line and insert
;  H          delete the rest of the line and insert
;  L          show the rest of the line and start again at its beginning
;  A          abandon the changes and start again
;  E          end, keep the changes
;  Q          quit, line unchanged
;  CR         show the rest of the line and end, keep the changes
;
EDLINE:	POP	AX		;drop PINLIN's return address (back to MAIN)
	MOV	BYTE PTR EDTFLG,LOW 0
EDRST:	CALL	EDLOAD		;BUF = text of the line, prompt shown
EDCMD:	XOR	CX,CX		;[CX]=repeat count
EDCNT:	CALL	KEYIN
	CMP	AL,LOW "0"
	JB	EDNDIG
	CMP	AL,LOW "9"
	JA	EDNDIG
	SUB	AL,LOW "0"
	CBW	
	XCHG	AX,CX
	MOV	DX,10D
	MUL	DX		;[AX]=count*10
	ADD	CX,AX		;[CX]=count*10+digit
	JMP	SHORT EDCNT
EDNDIG:	OR	CX,CX
	JNZ	EDHAVN
	INC	CX		;default count is 1
EDHAVN:	CMP	AL,LOW " "
	JE	EDSPC
	CMP	AL,LOW OFFSET CHRBKW
	JE	EDRUB
	CMP	AL,LOW OFFSET CHRDEL
	JE	EDRUB
	CMP	AL,LOW OFFSET CHRRET
	JNE	SHORT EDJ01
	JMP	EDCR
EDJ01:
	CMP	AL,LOW OFFSET CHRESC
	JNE	SHORT EDJ02
	JMP	EDCMD
EDJ02:		;ESC outside insert mode does nothing
	AND	AL,LOW 0DFH	;commands are case blind
	MOV	BX,OFFSET EDTAB
EDLKUP:	CMP	BYTE PTR CS:0[BX],LOW 0
	JE	EDBELL
	CMP	AL,BYTE PTR CS:0[BX]
	JE	EDGO
	ADD	BX,3
	JMP	SHORT EDLKUP
EDGO:	JMP	WORD PTR CS:1[BX]
EDBELL:	MOV	AL,LOW 7	;unknown command
	CALL	OUTDO
	JMP	SHORT EDCMD

EDTAB:	DB	"D"
	DW	OFFSET EDDEL
	DB	"C"
	DW	OFFSET EDCHG
	DB	"S"
	DW	OFFSET EDSRCH
	DB	"K"
	DW	OFFSET EDKILL
	DB	"I"
	DW	OFFSET EDINS
	DB	"X"
	DW	OFFSET EDEXT
	DB	"H"
	DW	OFFSET EDHACK
	DB	"L"
	DW	OFFSET EDLIST
	DB	"A"
	DW	OFFSET EDAGN
	DB	"E"
	DW	OFFSET EDEND
	DB	"Q"
	DW	OFFSET EDQUIT
	DB	0

;[n]space
EDSPC:	CALL	EDATND
	JB	SHORT EDJ03
	JMP	EDCMD
EDJ03:
	CALL	EDSHOW
	LOOP	EDSPC
	JMP	EDCMD

;[n]rubout
EDRUB:	CMP	BYTE PTR EDTPOS,LOW 0
	JNE	SHORT EDJ04
	JMP	EDCMD
EDJ04:
	DEC	BYTE PTR EDTPOS
	MOV	AL,LOW OFFSET CHRBKW
	CALL	OUTDO
	LOOP	EDRUB
	JMP	EDCMD

;[n]D
EDDEL:	CALL	EDATND
	JB	SHORT EDJ05
	JMP	EDCMD
EDJ05:
	CALL	EDBSL
EDDEL1:	CALL	EDATND
	JAE	EDDEL2
	CALL	EDCUR		;[AL]=character at the cursor
	CALL	OUTDO
	CALL	EDREMV
	LOOP	EDDEL1
EDDEL2:	CALL	EDBSL
	JMP	EDCMD

;[n]C
EDCHG:	CALL	EDATND
	JB	SHORT EDJ06
	JMP	EDCMD
EDJ06:		;at the end: ignored
EDCHG1:	CALL	EDATND
	JB	SHORT EDJ07
	JMP	EDCMD
EDJ07:
	CALL	KEYIN
	CALL	EDPOSP		;[BX] -> character at the cursor
	MOV	BYTE PTR 0[BX],AL
	CALL	EDSHOW
	LOOP	EDCHG1
	JMP	EDCMD

;[n]Sc
EDSRCH:	CALL	EDFIND		;[DL]=index of the n-th c, or the line length
EDSRC1:	CMP	BYTE PTR EDTPOS,DL
	JB	SHORT EDJ08
	JMP	EDCMD
EDJ08:
	CALL	EDSHOW
	JMP	SHORT EDSRC1

;[n]Kc
EDKILL:	CALL	EDFIND
	SUB	DL,BYTE PTR EDTPOS	;[DL]=characters to delete
	JA	SHORT EDJ09
	JMP	EDCMD
EDJ09:
	CALL	EDBSL
EDKIL1:	CALL	EDCUR
	CALL	OUTDO
	CALL	EDREMV
	DEC	DL
	JNZ	EDKIL1
	CALL	EDBSL
	JMP	EDCMD

;X - go to the end and insert
EDEXT:	CALL	EDATND
	JB	SHORT EDJ10
	JMP	EDINS
EDJ10:
	CALL	EDSHOW
	JMP	SHORT EDEXT

;H - delete the rest of the line and insert
EDHACK:	MOV	AL,BYTE PTR EDTPOS
	MOV	BYTE PTR EDTLEN,AL
				;fall into EDINS

;I - insert until ESC; CR ends the edit
EDINS:	CALL	KEYIN
	CMP	AL,LOW OFFSET CHRESC
	JNE	EDINS1
	JMP	EDCMD
EDINS1:	CMP	AL,LOW OFFSET CHRRET
	JNE	SHORT EDJ11
	JMP	EDCR
EDJ11:
	CMP	AL,LOW OFFSET CHRBKW
	JE	EDIRUB
	CMP	AL,LOW OFFSET CHRDEL
	JE	EDIRUB
	CMP	BYTE PTR EDTLEN,LOW OFFSET MAXLIN
	JAE	EDIFUL
	PUSH	AX
	MOV	BL,BYTE PTR EDTLEN	;open a gap at the cursor
	XOR	BH,BH
	ADD	BX,OFFSET BUF
EDIMOV:	MOV	AL,BL
	SUB	AL,LOW OFFSET BUF
	CMP	AL,BYTE PTR EDTPOS
	JBE	EDIMV2		;gap is at the cursor
	MOV	AL,BYTE PTR -1[BX]
	MOV	BYTE PTR 0[BX],AL
	DEC	BX
	JMP	SHORT EDIMOV
EDIMV2:
	INC	BYTE PTR EDTLEN
	POP	AX
	MOV	BYTE PTR 0[BX],AL
	CALL	EDSHOW
	JMP	SHORT EDINS
EDIFUL:	MOV	AL,LOW 7
	CALL	OUTDO
	JMP	SHORT EDINS
EDIRUB:	CMP	BYTE PTR EDTPOS,LOW 0
	JNE	SHORT EDJ12
	JMP	EDINS
EDJ12:
	DEC	BYTE PTR EDTPOS
	CALL	EDREMV
	MOV	AL,LOW OFFSET CHRBKW
	CALL	OUTDO
	JMP	SHORT EDINS

;L - show the rest and start again at the beginning
EDLIST:	CALL	EDREST
	CALL	CRDO
	CALL	EDPROM
	JMP	EDCMD

;A - abandon the changes
EDAGN:	CALL	CRDO
	JMP	EDRST

;Q - quit, the line stays as it was
EDQUIT:	CALL	CRDO
	JMP	READY

;CR - show the rest and end
EDCR:	CALL	EDREST
	CALL	CRDO
				;fall into EDEND

;E - end: enter the line as if it had been typed
EDEND:	CALL	CRDO
	MOV	BL,BYTE PTR EDTLEN
	XOR	BH,BH
	MOV	BYTE PTR BUF[BX],LOW 0
	MOV	DX,WORD PTR EDTLIN
	MOV	BX,OFFSET BUF
	STC			;there is a line number
	PUSHF	
	JMP	EDENT

;EDLOAD - decode line EDTLIN into BUF and show the prompt
;
EDLOAD:	MOV	DX,WORD PTR EDTLIN
	CALL	FNDLIN		;[CX] -> line
	JB	EDLD1
	POP	AX		;line vanished: back to command level
	JMP	READY
EDLD1:	MOV	BX,CX
	ADD	BX,4		;skip link and line number
	CALL	BUFLIN		;BUF = text, zero terminated
	MOV	BX,OFFSET BUF
EDLD2:	CMP	BYTE PTR 0[BX],LOW 0
	JE	EDLD3
	INC	BX
	JMP	SHORT EDLD2
EDLD3:	SUB	BX,OFFSET BUF
	MOV	BYTE PTR EDTLEN,BL
EDPROM:	MOV	BYTE PTR EDTPOS,LOW 0	;"nnn " and cursor at the start
	PUSH	CX
	MOV	BX,WORD PTR EDTLIN
	CALL	LINPRT
	MOV	AL,LOW " "
	CALL	OUTDO
	POP	CX
	RET	

;EDFIND - read c and find its n-th occurrence right of the cursor
; Entry - [CX]=n
; Exit  - [DL]=index of that occurrence, or the line length if not found
;
EDFIND:	CALL	KEYIN
	MOV	AH,AL
	MOV	DL,BYTE PTR EDTPOS
EDFND1:	INC	DL
	CMP	DL,BYTE PTR EDTLEN
	JAE	EDFND2
	MOV	BL,DL
	XOR	BH,BH
	CMP	AH,BYTE PTR BUF[BX]
	JNE	EDFND1
	LOOP	EDFND1
	RET	
EDFND2:	MOV	DL,BYTE PTR EDTLEN
	RET	

;EDATND - PSW.NC if the cursor is at the end of the line
;
EDATND:	MOV	AL,BYTE PTR EDTPOS
	CMP	AL,BYTE PTR EDTLEN
	RET	

;EDPOSP - [BX] -> character at the cursor
;
EDPOSP:	MOV	BL,BYTE PTR EDTPOS
	XOR	BH,BH
	ADD	BX,OFFSET BUF
	RET	

;EDCUR - [AL]=character at the cursor
;
EDCUR:	PUSH	BX
	CALL	EDPOSP
	MOV	AL,BYTE PTR 0[BX]
	POP	BX
	RET	

;EDSHOW - show the character at the cursor and move right
;
EDSHOW:	CALL	EDCUR
	CALL	OUTDO
	INC	BYTE PTR EDTPOS
	RET	

;EDREST - show the rest of the line (cursor goes to the end)
;
EDREST:	CALL	EDATND
	JAE	EDRSTX
	CALL	EDSHOW
	JMP	SHORT EDREST
EDRSTX:	RET	

;EDREMV - remove the character at the cursor
;
EDREMV:	PUSH	BX
	PUSH	AX
	CALL	EDPOSP
EDRMV1:	MOV	AL,BYTE PTR 1[BX]
	MOV	BYTE PTR 0[BX],AL
	INC	BX
	MOV	AL,BL
	SUB	AL,LOW OFFSET BUF
	CMP	AL,BYTE PTR EDTLEN
	JB	EDRMV1
	DEC	BYTE PTR EDTLEN
	POP	AX
	POP	BX
	RET	

;DECOUT - store [AX] as decimal digits at [DI], DI advanced.  AX,DX,BX used.
;
DECOUT:	MOV	BX,10D
	XOR	DX,DX
	DIV	BX		;[AX]=quotient, [DX]=last digit
	PUSH	DX
	OR	AX,AX
	JZ	DECOU1
	CALL	DECOUT
DECOU1:	POP	AX
	ADD	AL,LOW "0"
	STOSB
	RET	

;EDBSL - show a backslash
;
EDBSL:	MOV	AL,LOW "\"
	JMP	OUTDO

;LOAD ASCII:
;  PROGRAM LINE INPUT FROM DISK
;
DSKCHI:
	CALL	ISFLIO		; Set FLAGS.NZ if PTRFIL points to active file
	JNZ	ISLOAD		; BRIF LOAD statement
	RET			; If not, use console input
ISLOAD:	POP	AX		; Discard Return Address
	MOV	CL,LOW OFFSET BUFLEN	; Setup the maximum character count
	MOV	BX,OFFSET BUF	; Place we are going to store the line
LOPBUF:	CALL	INCHR		; Get a character from the file
				; (will call indskc and handle eof)
	MOV	BYTE PTR 0[BX],AL	; Store the character
	CMP	AL,LOW 13D	; Is it the end (a CR)
	JNZ	INOTCR		; Not a [CR]
	CMP	BYTE PTR -1[BX],LOW 10D	; Preceeded by a line feed?
	JZ	LOPBUF		; Yes, ignore the [CR]
	JMP	SHORT FINLIN	; No, this is the end of a line
INOTCR:
	OR	CL,CL
	JE	LTLONG		; Branch if line is too long to fit in BUF
	CMP	AL,LOW 10D	; LEADING LINE FEEDS MUST BE IGNORED
	JNZ	INOTLF
	CMP	CL,LOW OFFSET BUFLEN	; CL=BUFLEN if this is the 1st char on the line
	JZ	LOPBUF		; Branch if this was a leading line-feed
INOTLF:	INC	BX		; ADVANCE THE POINTER
	DEC	CL
	JMP	SHORT LOPBUF	; DO NEXT CHAR
FINLIN:
	MOV	BYTE PTR 0[BX],LOW 0
	MOV	BX,OFFSET BUF-1	; POINT AT BUFMIN
	RET	

LTLONG:	JMP	LBOERR		; Report LINE BUFFER OVERFLOW error

;SAVE ASCII:
;   PROGRAM LISTING CHAR OUTPUT TO DISK(CONVERT <LF> TO <LF><CR>)
;
OUTCH1:	CMP	AL,LOW OFFSET CHRLNF
	JZ	OUTCH0		; IS LF
	JMP	OUTDO
OUTCH0:	CALL	ISFLIO
	JNZ	OUTCH2		; branch if outputting to file
	CALL	OUTDO
	RET	

OUTCH2:	CALL	OUTDO
	MOV	AL,LOW OFFSET CHRRET
	CALL	OUTDO
	MOV	AL,LOW OFFSET CHRLNF
	RET	

CSEG	ENDS
	END
