; ROM BASIC program-store statements and interactive initialization on drive A:.
; Each header is followed by ceil(length/512) sectors of tokenized program.
; The zero sector after the last record is the append point.
DSEG segment public 'DATASG'
extrn TXTTAB:word,VARTAB:word,STKLOW:word,NLONLY:word,CHNFLG:word
extrn wanted:byte,found:word,copying:byte,nbytes:word,crc:word,oldBase:word
extrn sector:byte,payload:word
extrn AUTFLG:word
runLoad db ?
DSEG ends
CSEG segment byte public 'CODESG'
assume cs:CSEG,ds:DSEG
extrn DERDNA:near,DERFNF:near,DERIOE:near,DERDFL:near,DERNMF:near
extrn FCERR:near,SNERR:near,OMERR:near,READY:near,NEWSTT:near
public ROMCHOP,ROMCHLD,ROMCHSZ
extrn FRMEVL:near,FRESTR:near,CHNRET:near
extrn SCCPTR:near,RUNC:near,SCRTCH:near,OUTDO:near,CRDO:near
public DSKDSP, DFSTLD, PROCHK, PRODIR, PROSAV, PROLOD, CMPFBC
public FILES, KILL, NAME, RESET, SYSTEM, SYSTME, ROMSAVE, ROMLOAD, ROMRUN
DSKDSP dw 15 dup (offset DERDNA)
DFSTLD:
PROSAV:
PROLOD:
CMPFBC:
KILL:
NAME:
SYSTEM:
SYSTME:
        jmp DERDNA
PROCHK:
PRODIR:
RESET:
        ret

extrn clearName:near,nameChar:near,openVolume:near,scan:near,nextRecord:near
extrn fetchHeader:near,readPayload:near,appendRaw:near,initVolume:near
public rawError,rawForeign,rawFull,rawName
rawError:
        cmp copying,0
        je reportIO
        jmp invalidLoad
reportIO:
        jmp DERIOE
rawForeign:
        jmp DERDNA
rawFull:
        jmp DERDFL
rawName:
        jmp DERNMF
hName equ 4
; Parse an explicitly quoted, case-insensitive name of 1..12 printable bytes.
getName:
        cmp byte ptr [bx],34
        je nameStart
        jmp SNERR
nameStart:
        call clearName
nameNext:
        inc bx
        mov al,[bx]
        cmp al,34
        je nameEnd
        call nameChar
        jmp short nameNext
nameEnd:
        cmp di,offset wanted
        je rawName
        inc bx
        cmp byte ptr [bx],0
        je nameOk
        cmp byte ptr [bx],':'
        jne rawName
nameOk:
        ret

ROMSAVE:
        call getName
        push bx
        call openVolume
        mov ax,1
        call scan
        call SCCPTR
        mov si,TXTTAB
        mov payload,si
        mov oldBase,si
        mov dx,VARTAB
        sub dx,si
        mov nbytes,dx
        call appendRaw
        pop bx
        ret

ROMRUN:
        mov runLoad,1
        jmp short readProgram
ROMLOAD:
        mov runLoad,0
readProgram:
        call getName
        call verifyProgram
        jmp copyProgram

; CHAIN accepts a BASIC string expression and leaves BX at its delimiter.
ROMCHOP:
        call FRMEVL
        push bx
        call FRESTR
        mov si,[bx+1]
        xor ch,ch
        mov cl,[bx]
        jcxz invalidName
        push cx
        call clearName
        pop cx
chainName:
        lodsb
        call nameChar
        loop chainName
        call verifyProgram
        pop bx
        ret
invalidName:
        jmp DERNMF

; BX = top of string space, CX-DX = bytes of variables to preserve.
; BLTUC consumes the original register values after this check.
ROMCHSZ:
        mov ax,bx
        sub ax,cx
        add ax,dx
        sub ax,128
        jc tooLarge
        sub ax,TXTTAB
        jc tooLarge
        cmp ax,nbytes
        jbe tooLarge
        ret

verifyProgram:
        call openVolume
        mov ax,1
        call scan
        mov ax,found
        or ax,ax
        jnz loadFound
        jmp DERFNF
loadFound:
        call fetchHeader
        mov dx,nbytes
        mov bx,TXTTAB
        add bx,dx
        jc tooLarge
        add bx,128               ; interpreter working margin
        jc tooLarge
        cmp bx,STKLOW
        jb loadFits
tooLarge:
        jmp OMERR
loadFits:
        ; Verify the entire payload before replacing the current program.
        mov copying,0
        call readPayload
        cmp dx,crc
        je verified
        jmp DERIOE
verified:
        ret

ROMCHLD:
        mov byte ptr NLONLY,81h  ; CHNRET finishes the transfer with devices open
        mov runLoad,2
copyProgram:
        call SCRTCH
        mov ax,TXTTAB
        mov payload,ax
        mov copying,1
        call readPayload
        mov copying,0
        cmp dx,crc
        jne invalidLoad
        ; Rebase each line link. Check bounds and terminators before RUN.
        mov bx,TXTTAB
        mov di,bx
        add di,nbytes
        sub di,2
fixLine:
        mov ax,[bx]
        cmp bx,di
        je lastLine
        sub ax,oldBase
        jc invalidLoad
        add ax,TXTTAB
        jc invalidLoad
        mov si,ax
        sub ax,bx
        jb invalidLoad
        cmp ax,5
        jb invalidLoad
        cmp si,di
        ja invalidLoad
        cmp byte ptr [si-1],0
        jne invalidLoad
        mov [bx],si
        mov bx,si
        jmp short fixLine
lastLine:
        or ax,ax
        jnz invalidLoad
        add di,2
        mov VARTAB,di
        call RUNC
        cmp runLoad,2
        jne ordinaryLoad
        jmp CHNRET
ordinaryLoad:
        cmp runLoad,0
        je loadOnly
        jmp NEWSTT
loadOnly:
        jmp READY
invalidLoad:
        mov copying,0
        mov byte ptr CHNFLG,0
        mov byte ptr NLONLY,0
        call SCRTCH
        jmp DERIOE

; List only the newest revision of each name. Scan ahead without a RAM catalog.
FILES:
        push bx
        call openVolume
        mov ax,1
listNext:
        push ax
        call nextRecord
        jc listDone
        pop dx
        push ax
        mov si,offset sector+hName
        mov di,offset wanted
        mov cx,12
        rep movsb
        call scan
        cmp found,0
        jne listSkip
        mov si,offset wanted
        mov cx,12
listChar:
        lodsb
        or al,al
        jz listEnd
        push si
        push cx
        call OUTDO
        pop cx
        pop si
        loop listChar
listEnd:
        call CRDO
listSkip:
        pop ax
        jmp short listNext
listDone:
        pop ax
        pop bx
        ret
; Standalone, literal keyboard command. On a non-match BX still points one
; byte before BUF and the normal BASIC tokenizer receives the original line.
extrn ISFLIO:near,PINLIN:near
public ROMPROMPT
initText db 'INIT'
askInit db 'Erase programs on A:? Type YES: ',0
ROMPROMPT:
        cmp byte ptr AUTFLG,0
        jne promptReturn
        call ISFLIO
        jnz promptReturn
        lea si,[bx+1]
        call spaces
        mov di,offset initText
        mov cx,4
matchInit:
        lodsb
        and al,0dfh
        cmp al,cs:[di]
        jne promptReturn
        inc di
        loop matchInit
        mov dl,1
        cmp byte ptr [si],0
        je askErase
        cmp byte ptr [si],' '
        jne promptReturn
        call spaces
        cmp byte ptr [si],0
        je askErase
        mov ax,[si]
        cmp ax,3233h            ; "32"
        je lastDigit
        cmp ax,3237h            ; "72"
        jne promptReturn
        inc dl
lastDigit:
        cmp byte ptr [si+2],'0'
        jne promptReturn
        add si,3
        call spaces
        cmp byte ptr [si],0
        jne promptReturn
        jmp short askErase
promptReturn:
        clc
        ret
askErase:
        push dx
        mov si,offset askInit
askChar:
        mov al,cs:[si]
        inc si
        or al,al
        jz getAnswer
        push si
        call OUTDO
        pop si
        jmp short askChar
getAnswer:
        call PINLIN
        pop dx
        jc returnReady
        lea si,[bx+1]
        call spaces
        lodsw
        and ax,0dfdfh
        cmp ax,4559h
        jne returnReady
        lodsb
        and al,0dfh
        cmp al,'S'
        jne returnReady
        call spaces
        cmp byte ptr [si],0
        jne returnReady
        mov al,dl
        call initVolume
returnReady:
        stc
        ret
spaces:
        cmp byte ptr [si],' '
        jne promptReturn
        inc si
        jmp short spaces
CSEG ends
end
