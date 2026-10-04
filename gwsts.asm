; [ This translation created 10-Feb-83 by Version 4.3 ]

	.RADIX  8		; To be safe

CSEG	SEGMENT PUBLIC 'CODESG' 
	ASSUME  CS:CSEG

INCLUDE	OEM.INC

	TITLE   GWSTS - Statement support kept from GW-BASIC (parsing, DATE$/TIME$,
				; event-trap hooks)

COMMENT	*

--------- --- ---- -- ---------
COPYRIGHT (C) 1982 BY MICROSOFT
--------- --- ---- -- ---------

	Reduced for an MBASIC 5.28 style interpreter: no screen, graphics,
	sound, light pen, joystick or function key support.

        *

	.SALL
	.RADIX	10

	EXTRN	CHRGTR:NEAR,SYNCHR:NEAR,SNERR:NEAR,FCERR:NEAR,GETBYT:NEAR
	EXTRN	USERR:NEAR

IF	CPM86  
CPMXIO	MACRO	DFUN
	MOV	CL,LOW OFFSET DFUN
	INT	340O		;CPM86 system call
ENDM 
ENDIF 

DOSIO	MACRO	DFUN
	MOV	AH,LOW OFFSET DFUN
	INT	33		;MS-DOS system call
ENDM 
	GDAT=42D		;MS-DOS Get Date Function
	SDAT=43D		;MS-DOS Set Date Function
	GTIM=44D		;MS-DOS Get Time Function
	STIM=45D		;MS-DOS Set Time Function

	PUBLIC	GWWID,PUT,GET,CHKINT
IF	CPM86
DSEG	SEGMENT PUBLIC 'DATASG'
	EXTRN	DATIME:WORD,CLKOK:WORD
DSEG	ENDS
ENDIF
	EXTRN	DPUTG:NEAR,POLKEY:NEAR,GETWID:NEAR
DSEG	SEGMENT PUBLIC 'DATASG'
	ASSUME DS:DSEG
	EXTRN	LINLEN:WORD,WDTFLG:WORD
DSEG	ENDS

	COMMA=","
	CPAREN=")"

;GWWID: WIDTH n for the console.  Entered with [AL] = first character of the
; operand and [BX] = text pointer.
;
GWWID:	CALL	GETWID		;[AL]=1..255, error otherwise
	MOV	BYTE PTR LINLEN,AL
	MOV	BYTE PTR WDTFLG,AL
	RET	

;PUT and GET only exist for random disk files
;
PUT:	MOV	CX,1		;Set PUT flag
	JMP	DPUTG
GET:	XOR	CX,CX		;Set GET flag
	JMP	DPUTG

;CHKINT is called from NEWSTT; it only needs to notice CTL-C
;
CHKINT:	JMP	POLKEY		;does not return when CTL-C is seen


	SUBTTL  Parsing Routines for GWSTS
	PUBLIC	EOSCHK

;EOSCHK: Detect garbage beyond end of statement
;ENTRY - BX = text pointer
;EXIT  - AL = 0 & all other registers preserved or
;      - Exit on error through FCERR
;
EOSCHK:
	DEC	BX		;Back up text pointer
EOSCH1:
	CALL	CHRGTR		;Get next character (skipping blanks)
	JZ	EOSCKX		;End of statement
	JMP	SNERR		;Not EOS - error
EOSCKX:	RET	

	PAGE	
	SUBTTL DATE - Get/Set Date.

	PUBLIC	DATES,DATEF
DSEG	SEGMENT PUBLIC 'DATASG'
	EXTRN	DAYSPM:WORD
DSEG	ENDS

;DATE$="[M]M/[D]D/[YY]YY" or "[M]M-[D]D-[YY]YY"USA Date format
;
DATES:	CALL	PRSDAT		;CX=year, DH=month, DL=day
	JMP	SETDAT		;set system date

;X$=DATE$ returns "YYYY-MM-DD" if KANABS&KANADT else "MM-DD-YYYY"
;
DATEF:
	CALL	CHRGTR		;skip DATE$
	PUSH	BX		;Save Text pointer
	MOV	AL,LOW 10D
	CALL	STRINI		;Get space for 10 char string
	PUSH	DX		;save adr of string
	CALL	GETDAT		;CX=year, DH=month, DL=day
	POP	BX		;[BX]=adr of string
	SUB	CX,1900D	;Reduce year by two digits
	CMP	CL,LOW 100D	;See if in 20th century
	MOV	CH,LOW 19D	;Setup 20th century in case
	JB	DATEF2		;Brif so.
	SUB	CL,LOW 100D	;subtract into next century
	INC	CH		;21st century
DATEF2:
	MOV	AL,DH
	CALL	PUTCHR		;Store ascii month
	MOV	AL,LOW "-"
	CALL	PUTCH2		;put separater
	MOV	AL,DL
	CALL	PUTCHR		;Store ascii day
	MOV	AL,LOW "-"
	CALL	PUTCH2		;put separater
	MOV	AL,CH
	CALL	PUTCHR		;Store ascii century
	MOV	AL,CL
	CALL	PUTCHR		;Store ascii year.
	JMP	PUTNEW		;Put result and ret (Txt ptr on stack).

PUTCHR:
	AAM			;Convert to unpacked BCD
	XCHG	AL,AH
	OR	AX,30060O	;Add "0" bias to both digits.
	CALL	PUTCH2
	MOV	AL,AH
PUTCH2:
	MOV	BYTE PTR 0[BX],AL	;store char in string
	INC	BX
	RET	


;PRSDAT parses a string containing
;   "[YY]YY/MM/DD" if KANABS&KANADT else "MM/DD/[YY]YY"
; Exit - CX=year, DH=month, DL=day,
;         [BX]=new text pointer.  All other regs preserved.
;
PRSDAT:
	CALL	SYNCHR
	DB	OFFSET EQULTK	;Must be DATE$ = string
	CALL	FRMEVL
	PUSH	BX		;Save Text pointer
	CALL	FRESTR
	MOV	CL,BYTE PTR 0[BX]	;Save string len in [CL]
	CMP	CL,LOW 1	;String must not be null
	JB	DATERR		;Brif null str
	MOV	SI,WORD PTR 1[BX]	;[SI] has addr of string.
	MOV	BL,CL		;Working reg for string len.
	CALL	GNUM8		;[AX]=month
	MOV	DH,AL		;[DH] = month
	CALL	DATSEP		;skip / or -
	CALL	GNUM8		;[AL]=day of month
	MOV	DL,AL		;[DL] = day
	CALL	DATSEP		;skip / or -
	CALL	GNUM16		;[AX]=year (16 BITS)
	CMP	AX,1978D
	JNB	DATE2		;branch if .GE. 1978
	CMP	AX,100D
	JNB	DATERR		;error if between 100 and 1977
	CMP	AX,78D
	JNB	DATE1		;add 1900 if .GE. 78
	ADD	AX,100D		;add 2000 if .LE. 77
DATE1:	ADD	AX,1900D
DATE2:
	CMP	AX,2100D
	JNB	DATERR		;branch if year too large
	MOV	CX,AX		;CX=year
	POP	BX		;Text pointer
	RET			;Exit.

;DATSEP checks for a date separator (- or /) and returns if found.
;
DATSEP:
	OR	BL,BL
	JZ	DATERR		;Error if string empty.
	MOV	AL,BYTE PTR 0[SI]
	CMP	AL,LOW "/"
	JZ	DIGITX
	CMP	AL,LOW "-"
	JZ	DIGITX		;branch if found
	JMP	SHORT DATERR

GNUM8:	CALL	GNUM16		;[AX]=16-bit number
	OR	AH,AH
	JNZ	DATERR		;error if larger than 255
	RET	

GNUM16:	PUSH	CX		;save caller's [CX], [DX]
	PUSH	DX
	MOV	AX,0		;initialize accumulator
GNUML:	CALL	DIGIT		;[CX]=0..9
	JB	GNUMX		;branch if not legal digit
	MOV	DX,10D
	MUL	DX		;[AX]=[AX]*10
	JO	DATERR		;branch if overflow
	ADD	AX,CX		;add in new digit
	JMP	SHORT GNUML
GNUMX:	POP	DX
	POP	CX
RET2:	RET	

DIGIT:	CMP	BL,LOW 1	;End-of-string?
	JB	RET2		;Brif END-OF-STRING
	MOV	CL,BYTE PTR 0[SI]
	SUB	CL,LOW "0"
	JB	RET2		;branch if illegal digit
	CMP	CL,LOW 10D
	CMC	
	JB	RET2		;branch if illegal digit
	MOV	CH,LOW 0	;[CX]=digit
DIGITX:	DEC	BL		;Length -1
	INC	SI		;[SI] points to next byte in string
	RET	

DATERR:	JMP	FCERR

IF	CPM86
;DYOFYR converts YEAR, MONTH, DAY to binary DAY-OF-YEAR
; Entry - [CX]=binary year (19xx/20xx)
;         [DH]=binary month (1..12)
;         [DL]=binary day-of-month (1..31)
; Exit  - [BX]=binary day of year (0..364/365)
;         [CX] is preserved, all other registers are destroyed.
;
DYOFYR:	SUB	CX,1978D	;[CX]=year - 1978
	DEC	DL		;[DL]=day of month - 1
	DEC	DH		;[DH]=month - 1
	MOV	BL,DL
	XOR	BH,BH		;[BX]=day accumulator=day-of-month - 1
	MOV	AH,BH
	MOV	AL,DH		;[AX]=month - 1
	MOV	SI,AX		;[SI]=month - 1
	CALL	SETFEB		;DAYSPM(2)=28 or 29
	CMP	DH,LOW 12D
	JNB	DATERR		;error if month is too large
	CMP	DL,BYTE PTR DAYSPM[SI]
	JNB	DATERR		;error if day-of-month too large
	OR	SI,SI
MONTHL:	JNZ	MONTHS
	RET	
MONTHS:	MOV	AL,BYTE PTR DAYSPM-1[SI]
	ADD	BX,AX		;days=days+DAYSPM(month)
	DEC	SI
	JMP	SHORT MONTHL

;SETFEB sets DAYSPM(2) to 28 or 29 depending on year
;
SETFEB:	CALL	CKLEAP		;[AX]=1 if [CX]=leap-year
	ADD	AL,LOW 28D	;[AL]=29 if leap, 28 if not
	MOV	BYTE PTR DAYSPM+1,AL	;DAYSPM(2)=28 or 29
	RET	

;CKLEAP returns with [AX]=1 if [CX]+1978 is a leap year, else [AX]=0.
;
CKLEAP:	MOV	AH,LOW 0
	MOV	AL,CL
	AND	AL,LOW 3
	SUB	AL,LOW 2	;[AX]=0 if leap year
	JZ	CKLEA1		;branch if it is leap-year
	MOV	AL,LOW 377O
CKLEA1:	INC	AL
	RET	
ENDIF 

IF	CPM86  
;SETDAT sets the system clock's date.
; Entry - [CX]=year (19xx/20xx)
;         [DH]=month (1..12)
;         [DL]=binary day-of-month (1..31)
; Exit  - [BX] preserved.  All other registers destroyed.
;
SETDAT:	PUSH	BX		;save BX
	CALL	GDTIME		;get current date/time into DATIME
	CALL	DYOFYR		;[BX]=day of year (0..364/365)
				;[CX]=year - 1978
	OR	CX,CX		;test year
	JZ	YEARSX		;branch if 1978
	JMP	SHORT YEARS1
YEARSL:	CALL	CKLEAP		;[AX]=1 if CX is leap-year
	ADD	BX,AX		;days=days+1 if leap-lear
YEARS1:	ADD	BX,365D		;days=days+365
	LOOPNZ	YEARSL
YEARSX:	MOV	WORD PTR DATIME,BX	;DATIME=count of days since 1/1/1978
	CALL	SDTIME		;set current date/time from DATIME
	POP	BX		;restore text pointer
	RET	

;GETDAT returns with [CX]=year, DH=month, DL=day-of-month.
; Exit - BX, AX are used.
;
GETDAT:	CALL	GDTIME		;get current date/time into DATIME
	MOV	DX,WORD PTR DATIME	;[DX]=no of days since JAN 1,1978
	MOV	CX,0		;years=0
FNDYR:	CALL	CKLEAP		;[AX]=1 if leap-year
	ADD	AX,365D		;[AX]=366 if leap-year
	CMP	DX,AX
	JB	GOTYR		;branch if CX=year
	SUB	DX,AX		;days=days-365 or 366
	INC	CX		;year=year+1
	JMP	SHORT FNDYR

GOTYR:	CALL	SETFEB		;set DAYSPM(2)=28 or 29
	MOV	BX,0
	MOV	AH,BH
FNDMON:	MOV	AL,BYTE PTR DAYSPM[BX]	;[AX]=days in month BX
	INC	BX
	CMP	DX,AX
	JB	GOTMON		;branch if BX is month
	SUB	DX,AX
	JMP	SHORT FNDMON

GOTMON:	MOV	DH,BL		;[DH]=month (1..12)
	INC	DL		;[DL]=day of month (1..31)
	ADD	CX,1978D	;[CX]=year
	RET	
ENDIF 
IFE	CPM86
SETDAT:	PUSH	BX
	DOSIO	SDAT		;Give Date to MS-DOS.
	OR	AL,AL		;Date OK?
	JNZ	DATERR		;Brif not.
	POP	BX
	RET	

;GETDAT returns with [CX]=year, DH=month, DL=day-of-month.
; Exit - BX, AX are used.
;
GETDAT:	DOSIO	GDAT		;Get Date from MS-DOS
	RET	
ENDIF
	PAGE	
	SUBTTL TIME - Get/Set Time.

	PUBLIC	TIMES,TIMEF
	EXTRN	STRINI:NEAR,PUTNEW:NEAR,FCERR:NEAR
	EXTRN	CHRGTR:NEAR,SYNCHR:NEAR,GETYPR:NEAR,FRMEVL:NEAR,FRESTR:NEAR
DSEG	SEGMENT PUBLIC 'DATASG'
	EXTRN	DATIME:WORD,EQULTK:WORD
DSEG	ENDS

; TIME$=[H]H[:[M]M[:[S]S[:[T]T]]]
;
TIMES:	CALL	PRSTIM		;CH=hour, CL=min, DH=sec, DL=.01sec
	JMP	SETTIM		;set system time

;X$=TIME$ returns "HH:MM:SS"
;
TIMEF:
	CALL	CHRGTR		;skip TIME$ (it was CPI'ed in FRMEVL)
	PUSH	BX		;Save Text pointer
	MOV	AL,LOW 8D
	CALL	STRINI		;Get space for 8 char string
	PUSH	DX		;Save addr of string
	CALL	GETTIM		;CH=hour, CL=min, DH=sec
	POP	BX		;Restore addr of String
	MOV	AL,CH
	CALL	PUTCHR		;Store ascii hours
	MOV	AL,LOW ":"
	CALL	PUTCH2
	MOV	AL,CL
	CALL	PUTCHR		;Store ascii minutes
	MOV	AL,LOW ":"
	CALL	PUTCH2
	MOV	AL,DH
	CALL	PUTCHR		;Store ascii seconds.
	JMP	PUTNEW		;Put result and ret (Txt ptr on stack).

	EXTRN	FMULT:NEAR,CONIA:NEAR,FRCSNG:NEAR,FADD:NEAR,PUSHF:NEAR


;PRSTIM parses a string containing "HH[:MM[:SS[.TT]]]
; Exit - CH=hours, CL=minutes, DH=seconds, DL=.01 secs,
;         [BX]=new text pointer.  All other regs preserved.
;
PRSTIM:
	CALL	SYNCHR
	DB	OFFSET EQULTK	;Must be TIME$ = string
	CALL	FRMEVL
	PUSH	BX		;Save Text pointer
	CALL	FRESTR
	MOV	CL,BYTE PTR 0[BX]	;Save string len in [CL]
	CMP	CL,LOW 1	;String must not be null
	JB	TIMERR		;Brif null str
	MOV	SI,WORD PTR 1[BX]	;[SI] has addr of string.
	MOV	BL,CL		;Working reg for string len.
	CALL	GNUM8		;[AX]=hours
	CMP	AL,LOW 24D
	JNB	TIMERR
	MOV	CH,AL		;[CH] = hours
	CALL	TIMSEP
	CALL	GNUM8
	CMP	AL,LOW 60D
	JNB	TIMERR
	MOV	CL,AL		;[CL] = minutes
	CALL	TIMSEP
	CALL	GNUM8
	CMP	AL,LOW 60D
	JNB	TIMERR
	MOV	DH,AL		;[DH] = seconds.
	CALL	TIMSEP
	CALL	GNUM8
	CMP	AL,LOW 100D
	JNB	TIMERR
	MOV	DL,AH		;[DL] = 100ths.
	POP	BX		;Text pointer
	RET			;Exit.

TIMSEP:
	OR	BL,BL
	JZ	TIMSXX
	DEC	BL
	CLD			;Set to increment
	LODSB
	CMP	AL,LOW ":"
	JZ	TIMSXX
	CMP	AL,LOW "."
	JNZ	TIMERR
TIMSXX:
	RET	

TIMERR:	JMP	FCERR


IF	CPM86  
SETTIM:	CALL	GDTIME		;get current date/time into DATIME
	PUSH	BX		;save text pointer
	MOV	BX,OFFSET DATIME+2	;BX points to hours digit of buffer
	MOV	AL,CH
	CALL	BINBCD		;DT.HRS=BINBCD(CH)
	MOV	AL,CL
	CALL	BINBCD		;DT.MIN=BINBCD(CL)
	MOV	AL,DH
	CALL	BINBCD		;DT.SEC=BINBCD(DH)
	CALL	SDTIME		;set current date/time from DATIME
	POP	BX		;restore text pointer
	RET	

;BINBCD converts [AL] to 2-digit BCD and stores the result at [BX]
; Exit  - BX is incremented
;
BINBCD:
	PUSH	DX		;save caller's [DX]
	MOV	AH,LOW 0
	MOV	DL,LOW 10D
	DIV	DL		;[AL]=[AX]/10, [AH]=remainder
	ADD	AL,AL		;[AL]=1st digit * 2
	ADD	AL,AL		; * 4
	ADD	AL,AL		; * 8
	ADD	AL,AL		; * 16
	ADD	AL,AH		; + second digit
	POP	DX		;restore caller's [DX]
	JMP	PUTCH2

GETTIM:	CALL	GDTIME		;get current date/time into DATIME
	MOV	BX,OFFSET DATIME+2	;BX points to hours digit of buffer
	CALL	BCDBIN
	MOV	CH,AL		;[CH]=BCDBIN(DT.HRS)
	CALL	BCDBIN
	MOV	CL,AL		;[CL]=BCDBIN(DT.MIN)
	CALL	BCDBIN
	MOV	DH,AL		;[DH]=BCDBIN(DT.SEC)
	RET	

;GDTIME sets DATIME to the current date-time.
; Exit - All registers preserved.
;
GDTIME:	CALL	CLKCHK		;no clock: Illegal function call
	PUSH	ES
	PUSH	AX
	PUSH	BX
	PUSH	CX
	PUSH	DX
	CLD			;Because of Melco BIOS Bug
	MOV	DX,OFFSET DATIME
	CPMXIO	155D		;CPM86 system call
	JMP	SHORT SDTIMX

;SDTIME sets the system clock to DATIME
; Exit - All registers preserved.
;
SDTIME:	CALL	CLKCHK
	PUSH	ES
	PUSH	AX
	PUSH	BX
	PUSH	CX
	PUSH	DX
	MOV	DX,OFFSET DATIME
	CPMXIO	104D		;CPM86 system call
SDTIMX:	POP	DX
	POP	CX
	POP	BX
	POP	AX
	POP	ES
	RET	

;CLKCHK - DATE$ and TIME$ need a BDOS with a clock (CP/M-86 Plus, CCP/M)
;
CLKCHK:	TEST	BYTE PTR CLKOK,LOW 255D
	JZ	CLKERR
	RET	
CLKERR:	JMP	FCERR

;BCDBIN converts [[BX]] from 2-digit BCD to binary and
; returns it in [AL]
; Exit  - BX is incremented, AH, DL are destroyed.
;
BCDBIN:	MOV	AL,BYTE PTR 0[BX]
	INC	BX
	MOV	AH,AL		;[AH]=copy of input parameter
	AND	AL,LOW 360O	;[AL]=D1*16 (most significant digit)
	ROR	AL,1		;[AL]=D1*8
	MOV	DL,AL		;[DL]=D1*8
	ROR	AL,1		;[AL]=D1*4
	ROR	AL,1		;[AL]=D1*2
	ADD	AL,DL		;[AL]=D1*10
	AND	AH,LOW 17O	;[AH]=D2
	ADD	AL,AH		;[AL]=10*D1+D2=binary result
	RET	
ENDIF 
IFE	CPM86
SETTIM:	PUSH	BX
	DOSIO	STIM		;Give Time to MS-DOS.
	OR	AL,AL		;Date OK?
	JNZ	TIMERR		;Brif not.
	POP	BX
	RET	

GETTIM:	DOSIO	GTIM		;Get Time from MS-DOS
	RET	
ENDIF

CSEG	ENDS
	END
