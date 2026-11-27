; IBM BIOS teletype and keyboard. CONPOL consumes one ASCII character.
CSEG SEGMENT BYTE PUBLIC 'CODESG'
assume cs:CSEG
public CONOUT,CONKEY,CONPOL,LSTOUT
CONOUT:
        push ax
        push bx
        push bp
        mov ah,0eh
        mov bx,7
        int 10h
        pop bp
        pop bx
        pop ax
        ret
CONKEY:
        xor ah,ah
        int 16h
        or al,al
        jz CONKEY
        ret
CONPOL:
        mov ah,1
        int 16h
        jz noKey
        xor ah,ah
        int 16h
        or al,al
        ret
noKey:
        xor al,al
        ret
LSTOUT:
        push ax
        push dx
        xor dx,dx
        xor ah,ah
        int 17h
        pop dx
        pop ax
        ret
CSEG ends
end
