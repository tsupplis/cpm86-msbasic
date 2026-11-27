; IBM PC diskette bridge. A: is the OS filesystem, physical B: the ROM volume.
; PUT and GET accept normal, unprotected tokenized BASIC-86 SAVE files.
include cfg.inc
include msdosu.inc
CSEG segment byte public 'CODESG'
CSEG ends
DSEG segment public 'DATASG'
        org 100h                ; CP/M base page, or a copy of the DOS PSP tail
usageMsg db 'ROMXFER INIT 320|720 / PUT file.bas name / GET name file.bas',13,10,'$'
askMsg db 'Erase programs on B:? Type YES: $'
doneMsg db 'Done.',13,10,'$'
cancelMsg db 'Cancelled.',13,10,'$'
fileMsg db 'File error on A:.',13,10,'$'
existsMsg db 'Output already exists.',13,10,'$'
invalidMsg db 'Invalid binary BASIC program.',13,10,'$'
missingMsg db 'Program not found.',13,10,'$'
ioMsg db 'Volume damaged or BIOS I/O error.',13,10,'$'
volMsg db 'Missing or unsupported ROM volume signature.',13,10,'$'
fullMsg db 'Volume full.',13,10,'$'
largeMsg db 'Program exceeds available memory.',13,10,'$'
args dw 3 dup (?)
memEnd dw ?
fileEnd dw ?
pspSeg dw ?
outputNew db 0
answer db 8,0,8 dup (?)
fileFCB db 37 dup (0)
        db 384 dup (?)
stackTop label byte
; Raw module data is linked after this stack. File buffer starts at 1000h.
imageStart equ 1000h
textStart equ imageStart+1
extrn wanted:byte,found:word,nbytes:word,oldBase:word,crc:word
extrn payload:word,copying:byte,rawDrive:byte
DSEG ends
CSEG segment byte public 'CODESG'
assume cs:CSEG,ds:DSEG
extrn initVolume:near,openVolume:near,scan:near,appendRaw:near
extrn clearName:near,nameChar:near,fetchHeader:near,readPayload:near
public rawError,rawForeign,rawFull,rawName
entry:
        cld
IF CPM86
        mov ax,ds
        mov es,ax
        mov dx,ds:[6]
        cmp byte ptr ds:[8],0
        je setStack
ELSE
        mov bx,ds
        mov ax,seg DSEG
        mov es,ax
        mov si,80h
        mov di,si
        mov cx,128
        rep movsb
        mov dx,ds:[2]
        sub dx,ax
        mov ds,ax
        mov pspSeg,bx
        cmp dx,1000h
        jae fullSegment
        mov cl,4
        shl dx,cl
        jmp short setStack
ENDIF
fullSegment:
        mov dx,0ffffh
setStack:
        mov ss,ax
        mov sp,offset stackTop
        mov memEnd,dx
        mov rawDrive,1
        xor bx,bx
        mov bl,ds:[80h]
        cmp bl,127
        jae usage
        mov byte ptr [bx+81h],0
        mov si,81h
        mov di,offset args
splitArgs:
        lodsb
        cmp al,' '
        je splitArgs
        or al,al
        jz arguments
        cmp di,offset args+6
        jae usage
        mov ax,si
        dec ax
        stosw
wordLoop:
        mov al,[si-1]
        cmp al,' '
        je endWord
        or al,al
        jz arguments
        inc si
        jmp short wordLoop
endWord:
        mov byte ptr [si-1],0
        jmp short splitArgs
arguments:
        mov si,args
        cmp di,offset args+4
        jb usage
        mov bx,offset initWord
        call matches
        je initCommand
        cmp di,offset args+6
        jne usage
        mov bx,offset putWord
        call matches
        jne tryGet
        mov si,args+2
        call parseFile
        mov si,args+4
        call parseName
        jmp putProgram
tryGet:
        mov bx,offset getWord
        call matches
        jne usage
        mov si,args+4
        call parseFile
        mov si,args+2
        call parseName
        jmp getProgram
usage:
rawName:
        mov dx,offset usageMsg
        jmp finish
initCommand:
        cmp di,offset args+4
        jne usage
        mov si,args+2
        mov bx,offset smallSize
        call matches
        mov al,1
        je confirm
        mov bx,offset bigSize
        call matches
        jne usage
        mov al,2
confirm:
        push ax
        mov dx,offset askMsg
        call print
        mov dx,offset answer
        CALLOS 10
        mov dl,13
        CALLOS 2
        mov dl,10
        CALLOS 2
        pop ax
        cmp answer+1,3
        jne cancelled
        mov si,offset answer+2
        mov byte ptr [si+3],0
        mov bx,offset yesWord
        push ax
        call matches
        pop ax
        jne cancelled
        call initVolume
        jmp success
cancelled:
        mov dx,offset cancelMsg
        jmp finish
initWord db 'INIT',0
putWord db 'PUT',0
getWord db 'GET',0
smallSize db '320',0
bigSize db '720',0
yesWord db 'YES',0

; Compare DS:SI argument against CS:BX uppercase, preserving both offsets.
matches:
        push si
        push bx
matchByte:
        lodsb
        call upper
        cmp al,cs:[bx]
        jne matchDone
        inc bx
        or al,al
        jnz matchByte
matchDone:
        pop bx
        pop si
        ret
upper:
        cmp al,'a'
        jb upperDone
        cmp al,'z'
        ja upperDone
        sub al,32
upperDone:
        ret

parseName:
        call clearName
rawChar:
        lodsb
        or al,al
        jz rawEnd
        call nameChar
        jmp short rawChar
rawEnd:
        ret

; Only A: filenames. Reject separators, wildcards and device syntax.
parseFile:
        mov di,offset fileFCB
        mov al,1
        stosb
        mov al,' '
        mov cx,11
        rep stosb
        mov di,offset fileFCB+1
        cmp byte ptr [si+1],':'
        jne baseName
        lodsb
        call upper
        cmp al,'A'
        jne fileSyntax
        inc si
baseName:
        mov cx,8
        call filePart
        cmp di,offset fileFCB+1
        je fileSyntax
        or al,al
        jz fileParsed
        mov di,offset fileFCB+9
        mov cx,3
        call filePart
        or al,al
        jnz fileSyntax
fileParsed:
        ret
filePart:
        lodsb
        or al,al
        jz fileParsed
        cmp al,'.'
        je fileParsed
        jcxz fileSyntax
        call upper
        cmp al,'0'
        jb fileSyntax
        cmp al,'9'
        jbe storeChar
        cmp al,'_'
        je storeChar
        cmp al,'A'
        jb fileSyntax
        cmp al,'Z'
        ja fileSyntax
storeChar:
        stosb
        dec cx
        jmp short filePart
fileSyntax:
        jmp usage

mountScan:
        call openVolume
        mov ax,1
        jmp scan

putProgram:
        call mountScan
        mov dx,offset fileFCB
        CALLOS 15
        cmp al,0ffh
        jne fileOpen
        jmp fileError
fileOpen:
        mov bx,imageStart
readRecord:
        mov ax,bx
        add ax,128
        jc fileLarge
        cmp ax,memEnd
        ja fileLarge
        mov dx,bx
        CALLOS 26
        mov dx,offset fileFCB
        CALLOS 20
        cmp al,1
        je inputDone
IF CPM86 EQ 0
        cmp al,3                 ; DOS partial final record, zero-padded
        je readLast
ENDIF
        or al,al
        jnz fileErrorJump
        add bx,128
        jmp short readRecord
IF CPM86 EQ 0
readLast:
        add bx,128
ENDIF
inputDone:
        mov fileEnd,bx
        call closeFile
        call checkNative
        mov payload,textStart
        call appendRaw
        jmp success
fileLarge:
        mov dx,offset largeMsg
        jmp finish
fileErrorJump:
        jmp fileError

; Locate EOL while stepping over inline numeric operands, as BASIC's CHEAD
; does. The first link gives the saved TXTTAB. Verify every following link.
checkNative:
        cmp fileEnd,textStart+2
        jb badProgram
        cmp byte ptr ds:[imageStart],0ffh
        jne badProgram
        mov bx,textStart
nativeLine:
        mov si,fileEnd
        sub si,bx
        jc badProgram
        cmp si,2
        jb badProgram
        mov si,bx
        lodsw
        or ax,ax
        jz nativeEnd
        mov dx,ax
        add si,2
        jc badProgram
tokenByte:
        cmp si,fileEnd
        jae badProgram
        lodsb
        or al,al
        jz endLine
        cmp al,31
        ja tokenByte
        xor ah,ah
        mov di,ax
        mov al,cs:operandSize[di]
        add si,ax
        jc badProgram
        jmp short tokenByte
endLine:
        mov ax,si
        sub ax,textStart
        sub dx,ax
        jc badProgram
        cmp bx,textStart
        jne checkBase
        mov oldBase,dx
checkBase:
        cmp dx,oldBase
        jne badProgram
        mov bx,si
        jmp short nativeLine
nativeEnd:
        cmp si,fileEnd
        jae badProgram
        cmp byte ptr [si],1ah
        jne badProgram
        sub si,textStart
        mov nbytes,si
        ret
badProgram:
        mov dx,offset invalidMsg
        jmp finish
operandSize db 11 dup (0),2,2,2,2,1,12 dup (0),2,4,0,8

getProgram:
        call mountScan
        mov ax,found
        or ax,ax
        jnz gotName
        mov dx,offset missingMsg
        jmp finish
gotName:
        call fetchHeader
        mov ax,nbytes
        add ax,textStart+1
        jc getLarge
        add ax,127
        jc getLarge
        cmp ax,memEnd
        ja getLarge
        mov payload,textStart
        mov copying,1
        call readPayload
        cmp dx,crc
        je crcOK
        jmp rawError
crcOK:
        mov byte ptr ds:[imageStart],0ffh
        mov di,textStart
        add di,nbytes
        mov cx,128
        mov al,1ah
        rep stosb
        mov dx,offset fileFCB
        CALLOS 15
        cmp al,0ffh
        je createOutput
        call closeFile
        mov dx,offset existsMsg
        jmp finish
getLarge:
        jmp fileLarge
createOutput:
        mov dx,offset fileFCB
        CALLOS 22
        cmp al,0ffh
        je fileError
        mov outputNew,1
        mov bx,imageStart
        mov si,nbytes
        add si,2
writeRecord:
        mov dx,bx
        CALLOS 26
        mov dx,offset fileFCB
IF CPM86 EQ 0
        ; DOS sequential FCB writes use a selectable logical record length.
        ; Use random block write with one-byte records for exact file size.
        mov word ptr fileFCB+14,1
        mov cx,si
        CALLOS 40
        cmp cx,si
        jne fileError
        or al,al
        jnz fileError
ELSE
        CALLOS 21
        or al,al
        jnz fileError
        add bx,128
        sub si,128
        ja writeRecord
ENDIF
        call closeFile
        mov outputNew,0
success:
        mov dx,offset doneMsg
        jmp short finish
rawError:
        mov dx,offset ioMsg
        jmp short finish
rawForeign:
        mov dx,offset volMsg
        jmp short finish
rawFull:
        mov dx,offset fullMsg
        jmp short finish
fileError:
        cmp outputNew,0
        je fileReport
        mov dx,offset fileFCB
        CALLOS 16
        CALLOS 19
fileReport:
        mov dx,offset fileMsg
finish:
        call print
IF CPM86
        xor dl,dl
        CALLOS 0
ELSE
        push pspSeg
        xor ax,ax
        push ax
        retf
ENDIF
closeFile:
        mov dx,offset fileFCB
        CALLOS 16
        cmp al,0ffh
        je fileError
        ret
print:
        CALLOS 9
        ret
CSEG ends
end entry
