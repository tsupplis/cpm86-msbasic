; [ This translation created 10-Feb-83 by Version 4.3 ]

	.RADIX  8		; To be safe

CSEG	SEGMENT BYTE PUBLIC 'CODESG' 
	ASSUME  CS:CSEG

INCLUDE	OEM.INC

	TITLE   ITSA86 - Resident Initialization for I8086

COMMENT	*

--------- --- ---- -- --------- -----------
COPYRIGHT (C) 1982 BY MICROSOFT CORPORATION
--------- --- ---- -- --------- -----------

        by Len Oorthuys Microsoft Corp.
        *

;************************************************************************
;*                                                                      *
;*  NOTE: Any code linked after this module is discarded after          *
;*        Initialization of BASIC.                                      *
;*                                                                      *
;************************************************************************

	INCLUDE	GIO86U.INC
	.SALL


	INCLUDE	MSDOSU.INC


DSEG	SEGMENT PUBLIC 'DATASG'
	ASSUME DS:DSEG
	EXTRN	TEMP8:WORD,TXTTAB:WORD,NORFLG:WORD
DSEG	ENDS

	EXTRN	NODSKS:NEAR,LRUN:NEAR,LOAD:NEAR,READY:NEAR

	PUBLIC	WORDS
WORDS:	DB	" Bytes free"	;WORDS
	DB	0

	PAGE	
	SUBTTL  INITSA
	PUBLIC	INITSA
INITSA:
	CALL	NODSKS
	CALL	MAPINI		;Init the new memory map
	MOV	BX,WORD PTR TXTTAB
	DEC	BX
	MOV	WORD PTR 0[BX],0D
	MOV	BX,WORD PTR TEMP8	;POINT TO START OF COMMAND LINE
	MOV	AL,BYTE PTR 0[BX]	;GET BYTE POINTED TO
	OR	AL,AL		;IF ZERO, NO FILE SEEN
	JZ	GREADY
	TEST	BYTE PTR NORFLG,LOW 377O	;/NORUN?
	JNZ	NORUN
	JMP	LRUN		;TRY TO RUN FILE
NORUN:	JMP	LOAD		;load it only
GREADY:	JMP	READY
	PAGE	
	SUBTTL  Initialization Support Routines
DSEG	SEGMENT PUBLIC 'DATASG'		
	EXTRN	MSWFLG:WORD,MSWSIZ:WORD,NEWDS:WORD
	EXTRN	STKLOW:WORD,MEMSIZ:WORD,TOPMEM:WORD,SAVSEG:WORD,MAXMEM:WORD
	EXTRN	FILTAB:WORD
	EXTRN	FREFLG:WORD	;BYTES FREE message flag
	EXTRN	CPMMEM:WORD	;last paragraph we own (read through DS)
DSEG	ENDS

	EXTRN	CLEARC:NEAR,OMERR:NEAR
	EXTRN	LINPRT:NEAR,STROUT:NEAR,CRDO:NEAR	;COM


	PUBLIC	MAPCLC,MAPINI

;MAPINI - Set up the final memory map.
;Entry  - NEWDS  = final DS:
;         MSWSIZ = final MAXMEM
;Exit   - DS: and stack moved.
;
MAPINI:
;Move the stack to the end of the new memory map
	POP	BX		;Return address
	CLI			;disable external interrupts
				; while changing memory map
	MOV	AX,WORD PTR NEWDS
	MOV	SS,AX
	MOV	SP,WORD PTR MSWSIZ	;
	PUSH	BX		;Return address

;Move the data segment
	MOV	ES,AX		;NEWDS
	XOR	SI,SI
	MOV	CX,WORD PTR TXTTAB	;Amount of memory to move
	SHR	CX,1		;In words
	CLD	
	MOV	BX,DS
	CMP	AX,BX		;Test for direction of copy
	JB	BLKCPY		;brif destination is below source
	STD			;Copy up
	MOV	SI,WORD PTR TXTTAB	;starting from top
BLKCPY:
	MOV	DI,SI
 REP	MOVSW

;Set new data segment
	MOV	DS,AX		;NEWDS
	MOV	AX,DS
	MOV	WORD PTR SAVSEG,AX	;For PEEK/POKE
	STI			;enable external interrupts

;Insure zeros at TXTTAB
	MOV	BX,WORD PTR TXTTAB
	MOV	WORD PTR 0[BX],0D
	MOV	BYTE PTR 2[BX],LOW 0D	;Three zeros necessary

;Call CLEARC to set up stack and finalize the memory map
	MOV	AX,WORD PTR MSWSIZ
;Make sure that [TXTTAB]+<stack size>+32 does not overflow memory
	MOV	BX,WORD PTR TOPMEM
	SUB	BX,WORD PTR STKLOW	;BX=stack size
	JBE	GOMERR		;BRIF illegal stack(0 or less bytes)
	NEG	BX
	ADD	BX,AX		;BX=new stack bottom
	JNB	GOMERR		;BRIF MSWSIZ is less than stack size
	SUB	BX,32D		;Leave a little room for a program
	JB	GOMERR		;BRIF no room left
	CMP	BX,WORD PTR TXTTAB	;Is new MAXMEM big enough?
	JBE	GOMERR		;BRIF new MAXMEM smaller than data area
MAXRQ1:	MOV	BX,AX
	SUB	BX,WORD PTR MAXMEM	;Calc. seg. size difference
	MOV	WORD PTR MAXMEM,AX	;Memory request
	ADD	WORD PTR TOPMEM,BX
	ADD	WORD PTR STKLOW,BX
	ADD	WORD PTR FILTAB,BX
	ADD	WORD PTR MEMSIZ,BX
	POP	BX		;Return address (BX saved by CLEARC)
	CALL	CLEARC
	PUSH	BX		;Return address (BX saved by CLEARC)

;Set up program segment prefix
IFE	CPM86
	MOV	DX,DS
	MOV	AH,LOW 38D	;Function ^H26
	INT	33D		;MSDOS function request
ENDIF

;Print free bytes message
	TEST	BYTE PTR FREFLG,LOW 255D	;BYTES FREE message flag
	JNZ	MAPINX		;Exit - message not to be printed
	MOV	BX,WORD PTR MEMSIZ
	SUB	BX,WORD PTR TXTTAB
	DEC	BX
	DEC	BX
	CALL	LINPRT		;PRINT # OF BYTES FREE
	MOV	BX,OFFSET WORDS	;TYPE THE HEADING
	CALL	STROUT		;"BYTES FREE"
	CALL	CRDO		;PRINT CARRIAGE RETURN
MAPINX:	RET	

GOMERR:	JMP	OMERR
	PAGE	
	SUBTTL  End of the New CS:

;All code loaded after this label is resident only until routine MAPINI
;initializes the new memory map.

CSEND:

;MAPCLC - Calculate the final memory map limits.
;Entry  - MSWFLG = Flag nonzero when /M: option exists
;         MSWSIZ = /M: option size
;Exit   - NEWDS  = Final DS: address
;         MSWSIZ = Highest memory address (future MAXMEM)
;
MAPCLC:
IF	CPM86
	MOV	DX,DS		;CP/M-86: the data group stays where it was loaded
ELSE
;NEWDS = CS: + paragraphs of resident code (everything before CSEND)
	MOV	DX,OFFSET CSEND
	ADD	DX,15D		;Round to next higher paragraph
	MOV	CL,LOW 4D
	SHR	DX,CL
	MOV	CX,CS
	ADD	DX,CX
	JO	GOMERR
ENDIF
	MOV	WORD PTR NEWDS,DX

;Validate the /M option or calculate the maximum possible MAXMEM
;1. Calcualte maximum MAXMEM based on the NEWDS
;2. If there was no /M option then goto 4
;3. Compare /M to the maximum and declare an error if /M is larger
;4. Save the new memory size as MSWSIZ
	PUSH	BX		;Save text pointer
	MOV	BX,WORD PTR CPMMEM
	SUB	BX,DX		;Avail paragraphs
	JB	GOMERR
	MOV	DX,OFFSET 65535D/16D	;Max usable paragraphs
	CMP	BX,DX
	JB	MAXREQ		;More than enough
	MOV	BX,DX
MAXREQ:	MOV	CL,LOW 4D
	SHL	BX,CL		;DX has valid maximum bytes
	TEST	BYTE PTR MSWFLG,LOW 255D
	JZ	NOMOPT		;No memory option
	MOV	DX,WORD PTR MSWSIZ	;Get /M: size
	CMP	BX,DX
	JB	GOMERR		;Not enough for request
	MOV	BX,DX
NOMOPT:	MOV	WORD PTR MSWSIZ,BX	;New MAXMEM
;       ADDI    BX,^D256
;       JB      MAXRQ1                  ;BRIF very large MAXMEM, value OK
;       CMP     BX,TXTTAB               ;Is new MAXMEM big enough?
;       JBE     GOMERR                  ;BRIF new MAXMEM smaller than data area
	POP	BX
	RET	

;SEGOFF     Convert end of memory segment to offset from current DS
;
;   On entry:   BX=last segment in memory
;               DS=current data segment
;
;   On exit:    BX=offset from current segment to paragraph specified by BX
;               Other registers unchanged, flags modified
;
	PUBLIC	SEGOFF
	EXTRN	OMERR:NEAR

SEGOFF:	PUSH	CX
	MOV	CX,DS
	SUB	BX,CX		;[BX]=number of paragraphs free for DSEG
	JBE	SGOFER		;BRIF last segment is less than current
	MOV	CX,7777O	;[CX]=max num of paragraphs BASIC could use
	CMP	BX,CX
	JBE	LESS64		;Brif less than 64k bytes available
	MOV	BX,CX		;don't need more than 64k bytes
LESS64:
	MOV	CL,LOW 4
	SHL	BX,CL		;convert paragraphs to bytes
	POP	CX		;restore caller's CX
	RET	
SGOFER:	JMP	OMERR

CSEG	ENDS
	END
