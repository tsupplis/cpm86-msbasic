#!/usr/bin/env python3
"""Delete NAME=value assignments whose NAME is mentioned nowhere else.

Repeats until nothing changes (a removed switch can orphan the switches it was
defined from).  Comment lines that continue a removed assignment go with it.
"""
import glob, re, sys
from collections import Counter

files = sorted(glob.glob('*.asm') + glob.glob('*.inc'))
assign = re.compile(r'^\s*([A-Za-z_$@?][\w$@?]*)\s*=\s*[^;]*$')
word = re.compile(r'[A-Za-z_$@?][\w$@?]*')
KEEP = {'CPM86', 'SCP', 'DEBUG'}          # set by cfg.inc

def code(l):
    return l.split(';')[0]

removed_total = 0
while True:
    text = {f: open(f).read().split('\n') for f in files}
    cnt, defn = Counter(), Counter()
    for ls in text.values():
        for l in ls:
            for t in word.findall(code(l)):
                cnt[t.upper()] += 1
            m = assign.match(code(l))
            if m:
                defn[m.group(1).upper()] += 1
    dead = {n for n, c in defn.items() if cnt[n] == c and n not in KEEP}
    if not dead:
        break
    n_removed = 0
    for f in files:
        ls, out, i = text[f], [], 0
        while i < len(ls):
            m = assign.match(code(ls[i]))
            if m and m.group(1).upper() in dead:
                n_removed += 1
                i += 1
                while i < len(ls) and re.match(r'^\s+;', ls[i]):
                    i += 1
                continue
            out.append(ls[i])
            i += 1
        if out != ls:
            open(f, 'w').write('\n'.join(out))
    removed_total += n_removed
    print('pass: removed %d assignments (%d names)' % (n_removed, len(dead)))
print('total removed:', removed_total)
