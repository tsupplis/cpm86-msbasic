#!/usr/bin/env python3
"""Delete MACRO ... ENDM definitions that no source line invokes.

Repeats until stable (a macro only used by a removed macro goes too).
"""
import glob, re
from collections import Counter

files = sorted(glob.glob('*.asm') + glob.glob('*.inc'))
word = re.compile(r'[A-Za-z_$@?&%][\w$@?&%]*')
start = re.compile(r'^\s*([A-Za-z_$@?][\w$@?]*)\s+MACRO\b', re.I)

def code(l):
    return l.split(';')[0]

total = 0
while True:
    text = {f: open(f).read().split('\n') for f in files}
    cnt, defs = Counter(), Counter()
    for ls in text.values():
        for l in ls:
            for t in word.findall(code(l)):
                cnt[t.upper().lstrip('&')] += 1
            m = start.match(code(l))
            if m:
                defs[m.group(1).upper()] += 1
    dead = {n for n, c in defs.items() if cnt[n] == c and not n.startswith('?')}   # ?name macros are invoked through built names
    if not dead:
        break
    n_removed = 0
    for f in files:
        ls, out, i = text[f], [], 0
        while i < len(ls):
            m = start.match(code(ls[i]))
            if m and m.group(1).upper() in dead:
                depth = 1
                i += 1
                while i < len(ls) and depth:
                    c = code(ls[i]).strip().upper()
                    if re.match(r'^[\w$@?]*\s*MACRO\b', c) or re.match(r'^(IRP|IRPC|REPT)\b', c):
                        depth += 1
                    if re.match(r'^ENDM\b', c):
                        depth -= 1
                    i += 1
                n_removed += 1
                continue
            out.append(ls[i])
            i += 1
        if out != ls:
            open(f, 'w').write('\n'.join(out))
    total += n_removed
    print('pass: removed %d macros: %s' % (n_removed, ' '.join(sorted(dead))))
print('total removed:', total)
