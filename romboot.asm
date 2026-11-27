; INT 18h enters at F600:0000. The first 4 KiB belong to the BIOS.
CSEG SEGMENT BYTE PUBLIC 'CODESG'
assume cs:CSEG, ds:DSEG
extrn START:near
public BIBOOT,ROMSEED
BIBOOT:
        cli
        mov ax,100h
        mov ss,ax
        mov sp,0ff0h
        sti
        int 12h
        cmp ax,16
        jb noMemory
        cmp ax,68                ; 4 KiB reserved + one 64 KiB data segment
        jbe gotSize
        mov ax,68
gotSize:
        mov cl,6
        shl ax,cl                ; KiB to paragraphs
        dec ax
        mov bp,ax
        mov ax,100h
        mov es,ax
        xor ax,ax
        xor di,di
        mov cx,offset LSTVAR
        cld
        rep stosb
        push cs
        pop ds
        mov si,offset ROMSEED
seedNext:
        lodsw                    ; length, offset, bytes; zero length ends table
        mov cx,ax
        jcxz seeded
        lodsw
        mov di,ax
        rep movsb
        jmp short seedNext
seeded:
        push es
        pop ds
        mov CPMMEM,bp
        jmp START
noMemory:
        int 19h
        jmp short noMemory
ROMSEED label byte
CSEG ends
DSEG segment public 'DATASG'
extrn CPMMEM:word
public LSTVAR
LSTVAR label word
DSEG ends
end BIBOOT
