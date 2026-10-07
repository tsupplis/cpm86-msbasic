10 REM IVTDUMP - dump the 8086 interrupt vector table (0000:0000-03FF)
20 REM each vector is 4 bytes: offset (low,high) then segment (low,high)
30 DEF SEG=0
40 FOR I=0 TO 255
50 A=I*4
60 O=PEEK(A)+256*PEEK(A+1)
70 S=PEEK(A+2)+256*PEEK(A+3)
80 PRINT RIGHT$("0"+HEX$(I),2);" ";RIGHT$("000"+HEX$(S),4);":";RIGHT$("000"+HEX$(O),4);
90 IF I MOD 4=3 THEN PRINT ELSE PRINT "   ";
100 NEXT I
110 DEF SEG
120 SYSTEM

