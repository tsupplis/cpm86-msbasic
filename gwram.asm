; GWRAM - sign-on text and the interpreter variables not declared in GWDATA

	.RADIX  8		; To be safe

CSEG	SEGMENT BYTE PUBLIC 'CODESG' 
	ASSUME  CS:CSEG

INCLUDE	OEM.INC

	TITLE   GWRAM - Sign-on text and RAM declarations

COMMENT	*
        --------- --- ---- -- ---------
        COPYRIGHT (C) 1981 BY MICROSOFT
        --------- --- ---- -- ---------
        *
	.SALL
	.RADIX	10

	PUBLIC	HEDING,CERMSG

HEDING:	DB	"Microsoft BASIC Version 5.50A"
	ACRLF	
	DB	"Copyright 1977-2026 (C) by Microsoft"
	ACRLF	
	DB	"Under MIT license"
	ACRLF	
	DB	00O		;Terminate previous string.

CERMSG:	ACRLF			;Command line error message
	DB	"Error detected in command line"
	ACRLF	
	DB	00O

CSEG	ENDS

DSEG	SEGMENT PUBLIC 'DATASG'
	ASSUME DS:DSEG

;VAR declares an uninitialised variable, VARI a byte with an initial value
;
VAR	MACRO	NAME,SIZE
	PUBLIC	NAME
NAME	LABEL	WORD
	DB	SIZE DUP(?)
ENDM

VARI	MACRO	NAME,VALUE
	PUBLIC	NAME
NAME	LABEL	WORD
	DB	VALUE
ENDM

IF	CPM86
	VAR	CPMMEM,2	;last paragraph of the data group (the base
				;page is left as CP/M-86 built it)
ENDIF
	VARI	FREFLG,0	;non-zero: /NOBANNER, no heading nor BYTES FREE
	VARI	NORFLG,0	;non-zero: /NORUN, LOAD the command line program
	VARI	INITFG,0	;non-zero once initialisation is complete
	VARI	SEMFLG,0	;non-zero: INPUT; (no CRLF at end of input)
	VAR	LINLEN,1	;console width
	VAR	WDTFLG,1	;default width of SCRN:
	VAR	SAVLEN,2	;used by BLOAD, BSAVE
	VARI	CLKOK,0		;CP/M-86: non-zero if the BDOS has a clock (3.0+)
	VARI	EDTFLG,0	;non-zero: next program line input is an EDIT
	VAR	EDTLIN,2	;line being edited
	VAR	EDTPOS,1	;EDIT cursor (index into BUF)
	VAR	EDTLEN,1	;EDIT line length
	VAR	INLBEG,2	;line input: first byte the user may rub out
	VARI	INMAIN,0	;non-zero while MAIN waits for a line
	VARI	RUBFLG,0	;non-zero: a \...\ rubout display is open
	VAR	INLSP,2		;SP inside PINLIN (for CTL-C at the prompt)

	PUBLIC	FOPTSZ
	FOPTSZ=64D		;size of the device open options buffer
	VAR	FILOPT,FOPTSZ	;buffer for device open options
	VAR	LP1DCB,4*NMLPT	;LPT1 device control block (GLPDCB in GIOLPT)

	PUBLIC	KYBQSZ
	KYBQSZ=32D		;size of the type-ahead buffer
	VAR	KYBQDS,8	;type-ahead queue descriptor (see GIO86)
	VAR	KYBQUE,KYBQSZ	;type-ahead buffer

	VAR	MSWSIZ,2	;/M: value
	VAR	MSWFLG,1	;non-zero: /M: was given
	VAR	NEWDS,2		;final DS: after the code is trimmed

DSEG	ENDS
	END
