10 REM PSPDUMP - dump BASIC's DS:0000-00FF: the MS-DOS PSP or CP/M-86 base page
20 DEF SEG:DEF FNW(X)=PEEK(X)+256*PEEK(X+1)
30 DEF FNH$(X)=RIGHT$("000"+HEX$(X),4)
40 FOR L=0 TO 255 STEP 16
50 PRINT RIGHT$("0"+HEX$(L),2);": ";:A$=""
60 FOR J=0 TO 15:B=PEEK(L+J):PRINT RIGHT$("0"+HEX$(B),2);" ";
70 IF B<32 OR B>126 THEN A$=A$+"." ELSE A$=A$+CHR$(B)
80 NEXT J:PRINT A$:NEXT L:PRINT
90 IF PEEK(0)=&HCD AND PEEK(1)=&H20 THEN 200
100 PRINT "CP/M-86 base page"
110 PRINT "Data group  ";FNH$(FNW(9));", length ";FNW(6)+65536!*PEEK(8)
120 PRINT "Code group  ";FNH$(FNW(3));", length ";PEEK(0)+256*PEEK(1)+65536!*PEEK(2)
130 PRINT "8080 model  ";PEEK(5)
140 GOTO 300
200 PRINT "MS-DOS PSP (BASIC's copy, INT 21h/26h)"
210 PRINT "Memory top  ";FNH$(FNW(2))
220 PRINT "Terminate   ";FNH$(FNW(&HC));":";FNH$(FNW(&HA))
230 PRINT "Ctrl-Break  ";FNH$(FNW(&H10));":";FNH$(FNW(&HE))
240 PRINT "Crit. error ";FNH$(FNW(&H14));":";FNH$(FNW(&H12))
250 PRINT "Environment ";FNH$(FNW(&H2C));" (DOS 2+)"
300 D=PEEK(&H5C):N$="":FOR J=&H5D TO &H67:N$=N$+CHR$(PEEK(J)):NEXT
310 D$="":IF D THEN D$=CHR$(64+D)+":"
315 PRINT "FCB 1       ";D$;N$
325 N=PEEK(&H80):T$="":FOR J=1 TO N:T$=T$+CHR$(PEEK(&H80+J)):NEXT
330 PRINT "Tail        ";N;"bytes [";T$;"]"
340 SYSTEM
