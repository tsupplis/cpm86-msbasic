#!/usr/bin/env python3
r"""Drive a DOS program under emu2 through a pseudo terminal.

usage: runbas.py DIR PROGRAM FILE [--expect-option-error]
  DIR      directory to run in (the flat build directory)
  PROGRAM  program to start, e.g. mbasic86.exe
  FILE     text file; each line is typed followed by CR, then SYSTEM is sent.
           Escapes: \^X control-X, \e ESC, \k CTRL-C, \b backspace, \d DEL, \r CR, \\ backslash; a line
           ending in \c is sent without the trailing CR. A first line
           "#args: ..." passes command-line arguments; FILE's companion
           NAME.bas, if any, is copied into DIR first.

The terminal output is written to stdout with CRLF turned into LF.
"""
import errno, os, pty, select, signal, sys, time

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
        end = time.monotonic() + dur
        while time.monotonic() < end:
            r, _, _ = select.select([fd], [], [], 0.05)
            if r:
                try:
                    d = os.read(fd, 4096)
                except OSError as exc:
                    if exc.errno == errno.EIO:  # PTY closed by child
                        return False
                    raise
                if not d:
                    return False
                out += d
        return True

    try:
        alive = rd(1.0)
        for l in lines:
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
        if alive:
            # Only executed BASIC can produce this complete output line.
            marker = b'MBASIC-SESSION-COMPLETE'
            command = b'PRINT "MBASIC-SESSION-";"COMPLETE"'
            before = len(out)
            os.write(fd, command + b'\r')
            deadline = time.monotonic() + 5
            while marker not in out[before:].replace(b'\r', b'').split(b'\n'):
                if time.monotonic() >= deadline or not rd(0.1):
                    sys.exit('runner: missing BASIC completion marker')
            # Drain the completion command's Ok prompt before sending SYSTEM.
            if not rd(0.2):
                sys.exit('runner: early exit after completion marker')
            echo = out.find(command, before)
            if echo < 0:
                sys.exit('runner: completion command was not echoed')
            out = out[:echo]
            os.write(fd, b'SYSTEM\r')
            if rd(5):
                sys.exit('runner: BASIC did not exit')
        elif not ('--expect-option-error' in sys.argv[4:] and
                  out.strip() == b'Syntax error'):
            sys.exit('runner: emulator exited before the script finished')
        deadline = time.monotonic() + 5
        while True:
            child, status = os.waitpid(pid, os.WNOHANG)
            if child:
                break
            if time.monotonic() >= deadline:
                sys.exit('runner: emulator did not terminate')
            time.sleep(0.01)
        pid = None
        if os.waitstatus_to_exitcode(status) != 0:
            sys.exit('runner: emulator terminated unsuccessfully')
    except (SystemExit, OSError):
        sys.stderr.write(out[-2000:].decode('cp437'))
        raise
    finally:
        os.close(fd)
        if pid is not None:
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            os.waitpid(pid, 0)
    if os.environ.get('RAW'):
        for l in out.split(b'\n'):
            print(repr(l))
        return
    sys.stdout.write(out.decode('cp437').replace('\r\n', '\n').replace('\r', '\n'))

main()
