; Sequential BIOS floppy volume shared by ROM BASIC and ROMXFER.
include cfg.inc
CSEG segment byte public 'CODESG'
CSEG ends
DSEG segment public 'DATASG'
public wanted,tailSec,found,copying,nbytes,crc,oldBase,payload,sector,rawDrive
wanted db 12 dup (?)
tailSec dw ?
found dw ?
copying db ?
nbytes dw ?
crc dw ?
oldBase dw ?
payload dw ?
cursor dw ?
volCount dw ?
trackSize db ?
rawDrive db 0
sector db 512 dup (?)
IF ROMBAS EQ 0
dmaAlt db 512 dup (?)
ENDIF
DSEG ends
CSEG segment byte public 'CODESG'
assume cs:CSEG,ds:DSEG
extrn rawError:near,rawForeign:near,rawFull:near,rawName:near
public fetchHeader,openVolume,initVolume,nextRecord,scan,appendRaw,readPayload,clearName,nameChar
; Header layout: magic, 12-byte name, length, payload CRC, original TXTTAB,
; header CRC. Words are little endian. A volume has a separate signature.
hName equ 4
hSize equ 16
hCRC equ 18
hBase equ 20
hCheck equ 22
volume db 'MSBASRAW'


; Transfer one sector. ROM startup places the buffer below the DMA boundary.
; AX = linear sector, AH of operation in BP (0201h read, 0301h write).
readSec:
        push bp
        mov bp,0201h
        jmp short transfer
writeSec:
        push bp
        mov bp,0301h
transfer:
        push ax
        push bx
        push cx
        push dx
        push si
        push di
        push es
        push ds
        pop es
        cmp ax,volCount
        jae ioError
        mov si,ax
        mov di,3
retryIO:
        mov ax,si
        mov cl,trackSize
        div cl                   ; AL = track/head pair, AH = zero-based sector
        mov cl,ah
        inc cl
        xor dx,dx
        shr al,1
        rcl dh,1
        mov ch,al
        mov dl,rawDrive
        mov bx,offset sector
IF ROMBAS EQ 0
        ; The OS chooses DS. A floppy DMA transfer cannot cross a physical
        ; 64 KiB boundary. An adjacent sector always fits when the first fails.
        push cx
        mov ax,ds
        mov cl,4
        shl ax,cl
        pop cx
        add ax,bx
        cmp ax,0fe00h
        jbe dmaReady
        mov bx,offset dmaAlt
        cmp bp,0301h
        jne dmaReady
        call swapBuffer
dmaReady:
ENDIF
        mov ax,bp
        push bx
        int 13h
        pop bx
        jnc transferDone
        xor ax,ax
        mov dl,rawDrive
        int 13h
        dec di
        jnz retryIO
ioError:
        jmp rawError
IF ROMBAS EQ 0
swapBuffer:
        push si
        push di
        push cx
        mov di,offset dmaAlt
        mov si,offset sector
        cmp bp,0301h
        je dmaCopy
        xchg di,si
dmaCopy:
        mov cx,256
        rep movsw
        pop cx
        pop di
        pop si
        ret
ENDIF
transferDone:
IF ROMBAS EQ 0
        cmp bx,offset dmaAlt
        jne dmaDone
        cmp bp,0201h
        jne dmaDone
        call swapBuffer
dmaDone:
ENDIF
        pop es
        pop di
        pop si
        pop dx
        pop cx
        pop bx
        pop ax
        pop bp
        ret

; CRC-16/IBM over DS:SI, CX bytes, initial DX=FFFFh.
checksum:
        push ax
        push bx
        jcxz crcDone
crcByte:
        lodsb
        xor dl,al
        mov bl,8
crcBit:
        shr dx,1
        jnc crcSkip
        xor dx,0a001h
crcSkip:
        dec bl
        jnz crcBit
        loop crcByte
crcDone:
        pop bx
        pop ax
        ret

clearName:
        push ds
        pop es
        cld
        mov di,offset wanted
        mov cx,12
        xor ax,ax
        rep stosb
        mov di,offset wanted
        ret
nameChar:
        cmp al,34
        je badName
        cmp al,33
        jb badName
        cmp al,126
        ja badName
        cmp di,offset wanted+12
        jae badName
        cmp al,'a'
        jb nameCopy
        cmp al,'z'
        ja nameCopy
        sub al,32
nameCopy:
        stosb
        ret
badName:
        jmp rawName
openVolume:
        cld
        push ds
        pop es
        mov al,1
        call geometry
        xor ax,ax
        call readSec
        mov si,offset sector+8
        mov di,offset volume
        mov cx,8
volumeByte:
        lodsb
        cmp al,cs:[di]
        jne wrongVolume
        inc di
        loop volumeByte
        lodsb
geometry:
        mov trackSize,8
        mov volCount,640
        cmp al,1
        je geomDone
        cmp al,2
        jne wrongVolume
        mov trackSize,9
        mov volCount,1440
geomDone:
        ret
wrongVolume:
        jmp rawForeign


; AL = version selected at the console. Verify the last sector is readable
; before replacing the directory. Commit the volume signature last.
initVolume:
        push ax
        call geometry
        mov ax,volCount
        dec ax
        call readSec
        push ds
        pop es
        cld
        call blankSector
        mov ax,1
        call writeSec
        mov word ptr sector,18cdh
        mov word ptr sector+2,0feebh
        mov di,offset sector+8
        mov si,offset volume
        mov cx,8
initMagic:
        mov al,cs:[si]
        inc si
        stosb
        loop initMagic
        pop ax
        stosb
        mov word ptr sector+510,0aa55h
        xor ax,ax
        jmp writeSec

; Validate every header before trusting its length. AX = header sector.
; Return carry set on end marker, otherwise AX = following header.
nextRecord:
        call readSec
        mov si,offset sector
        cmp word ptr [si],0
        jne checkHeader
        mov cx,256
emptyWord:
        lodsw
        or ax,ax
        jne badHeader
        loop emptyWord
        stc
        ret
checkHeader:
        cmp word ptr [si],4142h
        jne badHeader
        cmp word ptr [si+2],3153h
        jne badHeader
        mov dx,0ffffh
        mov cx,hCheck
        call checksum
        cmp dx,word ptr sector+hCheck
        jne badHeader
        mov dx,word ptr sector+hSize
        cmp dx,2
        jb badHeader
        dec dx
        mov cl,9
        shr dx,cl
        add ax,dx
        add ax,2
        cmp ax,volCount
        jae badHeader
        clc
        ret
badHeader:
        jmp rawError

; AX = matching header found by scan. Publish the on-disk program metadata.
fetchHeader:
        call readSec
        mov dx,word ptr sector+hSize
        mov nbytes,dx
        mov dx,word ptr sector+hCRC
        mov crc,dx
        mov dx,word ptr sector+hBase
        mov oldBase,dx
        ret

; AX starts at the first header to search. Newest committed match wins.
scan:
        mov found,0
scanNext:
        mov tailSec,ax
        call nextRecord
        jc scanDone
        mov si,offset wanted
        mov di,offset sector+hName
        mov cx,12
        repe cmpsb
        jne scanNext
        mov dx,tailSec
        mov found,dx
        jmp short scanNext
scanDone:
        ret

blankSector:
        mov di,offset sector
        xor ax,ax
        mov cx,256
        rep stosw
        ret

appendRaw:
        mov si,payload
        mov dx,nbytes
        mov ax,dx
        dec ax
        mov cl,9
        shr ax,cl
        add ax,tailSec
        add ax,2                 ; reserve the next end marker as well
        cmp ax,volCount
        jb saveFits
        jmp rawFull
saveFits:
        mov ax,tailSec
        inc ax
        mov cursor,ax
        mov crc,0ffffh
saveLoop:
        call blankSector
        mov cx,512
        cmp dx,cx
        jae saveChunk
        mov cx,dx
saveChunk:
        sub dx,cx
        push dx
        push cx
        push si
        mov dx,crc
        call checksum
        mov crc,dx
        pop si
        pop cx
        mov di,offset sector
        rep movsb
        mov ax,cursor
        call writeSec
        inc cursor
        pop dx
        or dx,dx
        jnz saveLoop
        call blankSector
        mov ax,cursor
        call writeSec            ; old end marker stays intact until commit
        mov word ptr sector,4142h
        mov word ptr sector+2,3153h
        mov si,offset wanted
        mov di,offset sector+hName
        mov cx,12
        rep movsb
        mov ax,nbytes
        mov word ptr sector+hSize,ax
        mov ax,crc
        mov word ptr sector+hCRC,ax
        mov ax,oldBase
        mov word ptr sector+hBase,ax
        mov dx,0ffffh
        mov si,offset sector
        mov cx,hCheck
        call checksum
        mov word ptr sector+hCheck,dx
        mov ax,tailSec
        call writeSec
        ret

; Read twice, checksumming both passes. Copying selects copy vs verify only.
readPayload:
        mov ax,found
        mov bx,nbytes
        mov di,payload
        mov dx,0ffffh
readLoop:
        inc ax
        call readSec
        mov cx,512
        cmp bx,cx
        jae readChunk
        mov cx,bx
readChunk:
        sub bx,cx
        mov si,offset sector
        push cx
        call checksum
        pop cx
        cmp copying,0
        je readMore
        mov si,offset sector
        rep movsb
readMore:
        or bx,bx
        jnz readLoop
        ret

CSEG ends
end
