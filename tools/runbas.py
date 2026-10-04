#!/usr/bin/env python3
r"""Drive a DOS program under emu2 through a pseudo terminal.

usage: runbas.py DIR PROGRAM FILE
  DIR      directory to run in (the flat build directory)
  PROGRAM  program to start, e.g. mbasic.exe
  FILE     text file; each line is typed followed by CR, then SYSTEM is sent.
           Escapes: \^X control-X, \e ESC, \k CTRL-C, \b backspace, \d DEL, \r CR, \\ backslash; a line
           ending in \c is sent without the trailing CR. A first line
           "#args: ..." passes command-line arguments; FILE's companion
           NAME.bas, if any, is copied into DIR first.

The terminal output is written to stdout with CRLF turned into LF.
"""
import os, pty, select, signal, sys, time

def keys(line):
    out, i, cr = bytearray(), 0, True
    if line.endswith('\\c'):
        line, cr = line[:-2], False
    while i < len(line):
        c = line[i]
        if c == '\\' and i + 2 < len(line) and line[i + 1] == '^':
            out.append(ord(line[i + 2].upper()) & 0x1f)
            i += 3
            continue
        if c == '\\' and i + 1 < len(line):
            n = line[i + 1]
            out += {'e': b'\x1b', 'k': b'\x03', 'b': b'\x08', 'd': b'\x7f', 'r': b'\r', '\\': b'\\'}.get(n, ('\\' + n).encode())
            i += 2
            continue
        out += c.encode('latin1')
        i += 1
    if cr:
        out += b'\r'
    return bytes(out)


def main():
    cwd, prog, script = sys.argv[1:4]
    lines = open(script).read().split('\n')
    while lines and lines[-1] == '':
        lines.pop()
    args = []
    if lines and lines[0].startswith('#args:'):
        args = lines.pop(0)[6:].split()
    bas = os.path.splitext(script)[0] + '.bas'
    if os.path.exists(bas):
        with open(bas, 'rb') as f:
            data = f.read()
        with open(os.path.join(cwd, os.path.basename(bas)), 'wb') as f:
            f.write(data)
    pid, fd = pty.fork()
    if pid == 0:
        os.chdir(cwd)
        os.execvp('emu2', ['emu2', prog] + args)
    out = b''

    def rd(dur):
        nonlocal out
        end = time.time() + dur
        while time.time() < end:
            r, _, _ = select.select([fd], [], [], 0.05)
            if r:
                try:
                    d = os.read(fd, 4096)
                except OSError:
                    return False
                if not d:
                    return False
                out += d
        return True

    alive = rd(1.0)
    for l in lines + ['SYSTEM']:
        if not alive:
            break
        chunks = keys(l).split(b'\x1b')
        for n, part in enumerate(chunks):
            if n:
                os.write(fd, b'\x1b')
                rd(0.4)            # let emu2 see ESC on its own
            if part:
                os.write(fd, part)
        alive = rd(0.5)
    rd(1.0)
    try:
        os.kill(pid, signal.SIGKILL)
    except OSError:
        pass
    try:
        os.waitpid(pid, 0)
    except OSError:
        pass
    if os.environ.get('RAW'):
        for l in out.split(b'\n'):
            print(repr(l))
        return
    sys.stdout.write(out.decode('cp437').replace('\r\n', '\n').replace('\r', '\n'))

main()
