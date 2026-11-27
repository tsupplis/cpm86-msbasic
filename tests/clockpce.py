"""Test BASIC clock values on disposable copies of IBM PC guest disks.

Arguments: PCE configuration, system boot image, data image containing
the current MBASIC86.CMD, and clock mode (unsupported, minute or second).
"""
import argparse
from pathlib import Path
import re
import shutil
import tempfile

from xferpce import DiskGuest


class ClockGuest(DiskGuest):
    def screen(self):
        # DOS Plus scrolls by advancing the VGA display-start address.
        video = self.command('s video')
        cell = int(re.search(rb'VGA: ADDR=([0-9A-Fa-f]+)', video)[1], 16)
        self.command('save clock.bin bin b800:0 8000')
        page = (self.work/'clock.bin').read_bytes()[::2]
        cell %= len(page)
        visible = (page + page)[cell:cell+2000]
        rows = [visible[i:i+80].decode('cp437').rstrip() for i in range(0, 2000, 80)]
        # Most guests reserve row 25. DOS Plus can use it for BASIC output.
        if re.match(r'^\s*(?:V[0-9]|US[0-9])', rows[-1]) or 'Station=' in rows[-1]:
            rows[-1] = ''
        return rows

    def type_line(self, command):
        # Additional IBM keyboard keys used in clock literals and statements.
        keys = {':': '+shift semicolon -shift', '/': 'slash',
                '-': 'minus', ';': 'semicolon', '"': '+shift apostrophe -shift',
                ' ': 'space', '$': '+shift 4 -shift', '=': 'equal', '\n': 'return'}
        for c in command + '\n':
            result = self.command('key ' + keys.get(c, c))
            assert b'unknown key' not in result, result
            self.command('c 10000')


def test(cfg, boot, data, mode, work, program_drive, hard_disk):
    config = re.sub(r'path\s*=\s*"([^"]+)"',
                    lambda m: f'path = "{(cfg.parent/m[1]).resolve()}"', cfg.read_text())
    config = re.sub(r'memtest\s*=\s*\d+', 'memtest = 0', config)
    config = re.sub(r'disk \{[^{}]*\}', '', config)
    config = re.sub(r'"sdl[^"]*"', '"null"', config)
    for drive, image in zip((128 if hard_disk else 0, 1), (boot, data)):
        target = work / f'disk{drive}.img'
        shutil.copyfile(image, target)
        config += f'\ndisk {{ drive={drive} type="auto" file="{target}" }}\n'
    (work/'test.cfg').write_text(config)
    with ClockGuest(work) as g:
        g.cpm = False
        if hard_disk:
            for _ in range(3):
                g.command('c f000000')
        g.wait_for(r'[AC](?:\:\\)?[>:]')
        g.issue(program_drive + ':mbasic86', r'Microsoft BASIC Version 5\.50B[\s\S]*Ok')
        error = r'Illegal function call\nOk'
        if mode == 'unsupported':
            for command in ('print date$', 'print time$', 'date$="1/1/2000"', 'time$="12"'):
                g.issue(command, error)
        else:
            seconds = '37' if mode == 'second' else '00'
            for value, expected in [('1/1/78','01-01-1978'), ('2/29/00','02-29-2000'),
                                    ('3/1/2000','03-01-2000'), ('12/31/2099','12-31-2099')]:
                g.issue(f'date$="{value}":print date$', expected + r'\nOk')
            g.issue('time$="13:45:37":print date$;time$', '12-31-209913:45:' + seconds + r'\nOk')
            g.issue('date$="2/28/2001":print time$', '13:45:' + seconds + r'\nOk')
            for command in ('date$="2/29/2001"', 'date$="4/31/2000"', 'date$="12/1/2100"',
                            'date$="1/1/"', 'date$="1/1/2000x"', 'time$="24"',
                            'time$="12:60"', 'time$="12::3"', 'time$="1:2:3:4x"'):
                g.issue(command, error)
            g.issue('time$="0":print date$;time$', r'02-28-200100:00:00\nOk')
            # Poll the guest timer across midnight. Minute-only setters need
            # a full guest minute. Advance CPU cycles with a bounded wait.
            g.issue('10 if date$="12-31-1999" then 10', 'then 10')
            g.issue('20 print date$', r'20 print date\$')
            g.type_line('date$="12/31/1999":time$="23:59:59":run')
            for _ in range(500):
                g.command('c 1000000')
                rows = [line for line in g.screen() if line]
                if '01-01-2000' in rows:
                    break
            else:
                raise AssertionError(rows)
    print(f'PASS {boot.name} ({mode})')


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    for name in ('config', 'boot', 'data'):
        p.add_argument(name, type=Path)
    p.add_argument('mode', choices=('unsupported','minute','second'))
    p.add_argument('--program-drive', choices=('a', 'b'), default='b')
    p.add_argument('--hard-disk', action='store_true', help='boot the system image as drive 80h')
    args = p.parse_args()
    with tempfile.TemporaryDirectory() as td:
        test(args.config.resolve(), args.boot, args.data, args.mode, Path(td), args.program_drive, args.hard_disk)
