10 REM BEEP - 1 kHz beep on the PC speaker with OUT and INP
20 REM 8253 timer channel 2 (ports 42h/43h), speaker gate on port 61h
30 OUT &H43,182:N=1193180!/1000
40 OUT &H42,N AND 255:OUT &H42,INT(N/256)
50 X=INP(&H61):OUT &H61,X OR 3
60 FOR I=1 TO 500:NEXT
70 OUT &H61,X
80 SYSTEM
