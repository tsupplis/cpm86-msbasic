"""Exercise the ROM with the 1982 IBM XT BIOS in PCE. See README for usage."""
import argparse
import os
from pathlib import Path
import pty
import re
import select
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
SIZE = 512


class XT:
    def __init__(self, work):
        self.work = work
        self.monitor, child = pty.openpty()
        self.process = subprocess.Popen(
            ['pce-ibmpc', '-c', 'test.cfg', '-t', 'null', '-g', 'vga'],
            cwd=work, stdin=child, stdout=child, stderr=child)
        os.close(child)

    def __enter__(self):
        try:
            self.prompt()
            self.ready()
            assert any('Microsoft BASIC' in line for line in self.screen())
            return self
        except BaseException:
            self.__exit__(None, None, None)
            raise

    def __exit__(self, *args):
        try:
            os.write(self.monitor, b'q\n')
            deadline = time.monotonic() + 5
            while self.process.poll() is None and time.monotonic() < deadline:
                if select.select([self.monitor], [], [], 0.05)[0]:
                    try:
                        os.read(self.monitor, 16384)
                    except OSError:
                        break
            self.process.wait(timeout=2)
        finally:
            if self.process.poll() is None:
                self.process.kill()
                self.process.wait()
            os.close(self.monitor)

    def prompt(self):
        output = bytearray()
        deadline = time.monotonic() + 15
        while time.monotonic() < deadline:
            if select.select([self.monitor], [], [], 0.01)[0]:
                output.extend(os.read(self.monitor, 16384))
            elif output.endswith(b'\n-'):
                return output
        raise TimeoutError('PCE monitor did not return')

    def command(self, command):
        os.write(self.monitor, command.encode('ascii') + b'\n')
        return self.prompt()

    def ready(self):
        # IBM XT BIOS 11/08/82 INT 16h loop waiting for the next keystroke.
        for _ in range(120):
            if re.search(rb'F000:E84[029D] ', self.command('c 100000')):
                return
        raise AssertionError(self.screen())

    def screen(self):
        self.command('save screen.bin bin b800:0 fa0')
        data = (self.work / 'screen.bin').read_bytes()[::2]
        return [data[i:i+80].decode('cp437').rstrip() for i in range(0, 2000, 80)]

    def type_line(self, command):
        keys = {'"': '+shift apostrophe -shift', ' ': 'space', '*': '+shift 8 -shift',
                '.': 'period', ',': 'comma', '=': 'equal', '$': '+shift 4 -shift',
                '(': '+shift 9 -shift', ')': '+shift 0 -shift', '\n': 'return'}
        for char in command + '\n':
            result = self.command('key ' + keys.get(char, char))
            assert b'unknown key' not in result, result
            self.command('c 10000')

    def line(self, command):
        self.type_line(command)
        self.ready()

    def expect(self, line):
        screen = self.screen()
        assert line in screen, '\n'.join(screen)


def test_chain(xt):
    xt.line('10 print n')
    xt.line('20 print s$')
    xt.line('30 print a(2)')
    xt.line('40 print z')
    xt.line('save "target"')
    xt.line('new')
    xt.line('10 n=71')
    xt.line('20 s$="carried"')
    xt.line('30 a(2)=38')
    xt.line('40 z=92')
    xt.line('50 common n,s$,a()')
    xt.line('60 f$="target"')
    xt.line('70 chain f$')
    xt.line('run')
    result = '\n'.join(xt.screen())
    assert ' 71\ncarried\n 38\n 0\nOk' in result, result
    xt.line('z=812')
    xt.line('chain "target",40,all')
    xt.expect(' 812')
    xt.line('chain "target",999')
    xt.expect('Undefined line number')
    xt.line('chain "absent"')
    xt.expect('File not found')
    xt.line('chain merge "target"')
    xt.expect('Illegal function call')


def configuration(config, rom):
    romdir = config.parent / 'rom'
    cfg = config.read_text().replace('path = "rom"', f'path = "{romdir}"')
    cfg = cfg.replace('ibm-basic-1.10.rom', str(rom))
    cfg = re.sub(r'patch_bios_int19\s*=\s*1', 'patch_bios_int19 = 0', cfg)
    cfg = re.sub(r'disk \{[^{}]*\}', '', cfg)
    cfg = re.sub(r'"sdl[^"]*"', '"null"', cfg)
    return cfg


def test(config, rom, work):
    cfg = configuration(config, rom)
    configfile = work / 'test.cfg'
    configfile.write_text(cfg)
    with XT(work) as xt:
        xt.line('print 7*9')
        xt.expect(' 63')
    print('PASS diskless boot and arithmetic', flush=True)

    disk = work / 'raw.img'
    subprocess.run([sys.executable, ROOT/'tools/mkraw.py', disk], check=True)
    configfile.write_text(cfg + '\ndisk { drive=0 type="auto" file="raw.img" }\n')
    with XT(work) as xt:
        xt.line('10 print 13')
        xt.line('save "demo"')
        xt.line('10 print 1234')
        for n in range(20, 100, 10):
            xt.line(str(n) + ' rem ' + 'x'*65)
        xt.line('save "demo"')
        xt.line('new')
        xt.line('files')
        assert xt.screen().count('DEMO') == 1
        xt.line('load "demo"')
        xt.line('run')
        xt.expect(' 1234')
    print('PASS multi-sector SAVE, replacement, FILES, LOAD and RUN', flush=True)

    with XT(work) as xt:
        xt.line('run "demo"')
        xt.expect(' 1234')
        xt.line('load "absent"')
        xt.expect('File not found')
    print('PASS cold reload and missing name', flush=True)

    with XT(work) as xt:
        test_chain(xt)
    print('PASS CHAIN, COMMON, start line, ALL and errors', flush=True)

    damaged = bytearray(disk.read_bytes())
    # First one-sector program occupies sectors 1 and 2. The second starts at 3.
    assert damaged[3*SIZE:3*SIZE+4] == b'BAS1'
    damaged[4*SIZE+7] ^= 1
    disk.write_bytes(damaged)
    with XT(work) as xt:
        xt.line('10 print 37')
        for verb in ('chain', 'load'):
            xt.line(f'{verb} "demo"')
            lines = [line for line in xt.screen() if line]
            assert lines[-3:] == [f'{verb} "demo"', 'Device I/O Error', 'Ok'], lines
        xt.line('run')
        xt.expect(' 37')
    print('PASS damaged program detected before replacing RAM program', flush=True)

    damaged[8] ^= 1
    disk.write_bytes(damaged)
    with XT(work) as xt:
        xt.line('10 print 37')
        for verb in ('save', 'load', 'run', 'chain'):
            cmd = f'{verb} "foreign"'
            xt.line(cmd)
            assert [s for s in xt.screen() if s][-3:] == [cmd, 'Device Unavailable', 'Ok']
        xt.line('init=21')
        xt.line('print init')
        xt.expect(' 21')
        xt.line('20 init')
        xt.line('run')
        xt.expect('Syntax error in 20')
        xt.line('init 320')
        xt.line('no')
    assert disk.read_bytes() == damaged
    print('PASS foreign disk protection, INIT variable, numbered line and cancellation', flush=True)

    with XT(work) as xt:
        xt.line('init 320')
        xt.line('yes')
        xt.line('files')
        assert [s for s in xt.screen() if s][-2:] == ['files', 'Ok']
        xt.line('10 print 91')
        xt.line('save "fresh"')
        xt.line('new')
        xt.line('run "fresh"')
        xt.expect(' 91')
    assert disk.read_bytes()[8:17] == b'MSBASRAW\x01'
    print('PASS interactive initialization and reuse', flush=True)


    # Reuse the INT 18h boot stub, with no volume signature.
    blank = bytearray(720 * 1024)
    blank[:4] = damaged[:4]
    blank[510:512] = damaged[510:512]
    disk.write_bytes(blank)
    with XT(work) as xt:
        xt.line('init 720')
        xt.line('yes')
        xt.line('10 print 720')
        xt.line('save "large"')
        xt.line('new')
        xt.line('run "large"')
        xt.expect(' 720')
    media = disk.read_bytes()
    assert media[8:17] == b'MSBASRAW\x02'
    assert media[SIZE:SIZE+9] == b'BAS1LARGE'
    print('PASS 720 KiB last-sector probe, initialization, SAVE and named RUN', flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('config', type=Path, help='cpm86-hacking/cpm86.cfg (IBM XT 11/08/82)')
    args = parser.parse_args()
    with tempfile.TemporaryDirectory() as tmp:
        test(args.config.resolve(), ROOT/'build/rom/mbasic.rom', Path(tmp))
