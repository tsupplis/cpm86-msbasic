"""Pack linked code and sparse RAM initializers into the IBM BASIC ROM window."""
from pathlib import Path
import re
import struct
import sys

exe, mapfile, output = map(Path, sys.argv[1:])
mz = exe.read_bytes()
last, pages, relocs, header = struct.unpack_from('<4H', mz, 2)
if mz[:2] != b'MZ' or relocs:
    sys.exit('ROM requires a relocation-free MZ image')
image = mz[header * 16:(pages - 1) * 512 + (last or 512)]
symbols = mapfile.read_text(encoding='ascii')
seed = int(re.search(r'^\s*0000:([0-9A-F]+)\s+ROMSEED\s*$', symbols, re.M)[1], 16)
data = int(re.search(r'^\s*([0-9A-F]+)H\s+\w+H\s+\w+H\s+DSEG\b', symbols, re.M)[1], 16)
if not seed <= data < len(image) or any(image[seed:data]):
    sys.exit('ROMSEED must follow all resident code')
rom = bytearray(image[:seed])
for run in re.finditer(rb'[^\x00]+(?:\x00{1,4}[^\x00]+)*', image[data:]):
    rom.extend(struct.pack('<HH', len(run[0]), run.start()))
    rom.extend(run[0])
rom.extend(b'\x00\x00')
print(f'ROM uses {len(rom)} of 32768 bytes')
if len(rom) >= 32768:
    sys.exit('IBM BASIC ROM window exceeded')
rom.extend(b'\xff' * (32768 - len(rom)))
rom[-1] = (rom[-1] - sum(rom)) & 255
output.write_bytes(rom)
