#!/usr/bin/env python3
"""Turn the linked MBASIC86.EXE into an MS-DOS COM file.

usage: mkcom.py EXE COM

The EXE has no relocations and its image starts at CS:0000 with the 256 byte
gap (ORG 256) where the PSP lives.  MS-DOS loads a COM file at PSP:0100 with
CS=DS=ES=SS=PSP and jumps to 0100, where gwmain has a JMP BIBOOT.  The COM is
therefore the image without the EXE header and without the first 256 bytes.
"""
import sys

exe, out = sys.argv[1:3]
d = open(exe, 'rb').read()
if d[:2] != b'MZ':
    sys.exit('mkcom: %s is not an EXE' % exe)
if int.from_bytes(d[6:8], 'little'):
    sys.exit('mkcom: %s has relocations, cannot make a COM' % exe)
hdr = int.from_bytes(d[8:10], 'little') * 16
last = int.from_bytes(d[2:4], 'little')
pages = int.from_bytes(d[4:6], 'little')
size = pages * 512 - (512 - last if last else 0)
image = d[hdr:size]

if any(image[:256]):
    sys.exit('mkcom: %s has code or data below offset 0100' % exe)
if image[256] != 0xE9:
    sys.exit('mkcom: %s has no JMP at offset 0100' % exe)
com = image[256:]
if len(com) > 0xFF00:
    sys.exit('mkcom: image larger than a COM file allows')
open(out, 'wb').write(com)
