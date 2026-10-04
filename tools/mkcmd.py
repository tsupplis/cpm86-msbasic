#!/usr/bin/env python3
"""Turn the linked MBASIC86.EXE into a CP/M-86 compact model CMD file.

usage: mkcmd.py EXE MAP CMD

The EXE has no relocations: its image is CSEG followed by DSEG (see the MAP).
CSEG becomes the code group, DSEG the data group.  CP/M-86 puts the base page
in the first 256 bytes of the data group, which DSEG reserves for it (BEGDSG),
and gives the data group up to 64K so BASIC can use it for program and data.
"""
import re
import sys

exe, mapf, out = sys.argv[1:4]
d = open(exe, 'rb').read()
if d[:2] != b'MZ':
    sys.exit('mkcmd: %s is not an EXE' % exe)
if int.from_bytes(d[6:8], 'little'):
    sys.exit('mkcmd: %s has relocations, cannot make a CMD' % exe)
hdr = int.from_bytes(d[8:10], 'little') * 16
last = int.from_bytes(d[2:4], 'little')
pages = int.from_bytes(d[4:6], 'little')
size = pages * 512 - (512 - last if last else 0)
image = d[hdr:size]

dseg = None
for line in open(mapf, encoding='latin1'):
    m = re.match(r'\s*([0-9A-F]{5})H\s+([0-9A-F]{5})H\s+[0-9A-F]{5}H\s+DSEG\b', line)
    if m:
        dseg = int(m.group(1), 16)
if dseg is None or dseg % 16:
    sys.exit('mkcmd: no paragraph aligned DSEG in %s' % mapf)

code, data = image[:dseg], image[dseg:]
pad = lambda b: b + bytes(-len(b) % 16)
code, data = pad(code), pad(data)
cpar, dpar = len(code) // 16, len(data) // 16
if cpar > 0xFFF or dpar > 0xFFF:
    sys.exit('mkcmd: group larger than 64K')

def group(kind, length, minimum, maximum):
    return bytes([kind]) + b''.join(v.to_bytes(2, 'little') for v in (length, 0, minimum, maximum))

header = group(1, cpar, cpar, cpar) + group(2, dpar, dpar + 0x100, 0x1000)
header += bytes(128 - len(header))
open(out, 'wb').write(header + code + data)
print('CMD   %s: code %d bytes, data %d bytes (up to 64K)' % (out.split('/')[-1], len(code), len(data)))
