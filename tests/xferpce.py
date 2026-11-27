"""Round-trip a native BASIC program between an OS and the ROM in PCE.

Supply a bootable image with the newly built ROMXFER and MBASIC86 in A:.
The test boots a private copy and creates a separate raw B: disk.
"""
import argparse
from pathlib import Path
import re
import shutil
import tempfile

from rompce import ROOT, XT, configuration


class DiskGuest(XT):
    def __enter__(self):
        try:
            self.prompt()
            return self
        except BaseException:
            self.__exit__(None, None, None)
            raise

    def wait_for(self, pattern):
        for _ in range(150):
            self.command('c 100000')
            rows = self.screen()
            if self.cpm:
                rows = rows[:24]  # CP/M keeps its status on the bottom row
            display = '\n'.join(x for x in rows if x)
            if re.search(pattern + r'\Z', display, re.IGNORECASE):
                return display
        raise AssertionError(display)

    def issue(self, command, result):
        self.type_line(command)
        self.wait_for(result)


def test(config, boot, target, work):
    os_disk = work / 'boot.img'
    raw = work / 'raw.img'
    shutil.copyfile(boot, os_disk)
    raw.write_bytes(bytes(320 * 1024))
    cfg = configuration(config, ROOT/'build/rom/mbasic.rom')
    cfg_file = work/'test.cfg'
    os_cfg = cfg + '\ndisk { drive=0 type="auto" file="boot.img" }\n' + \
                   'disk { drive=1 type="auto" file="raw.img" }\n'
    prompt = r'A[>:]'
    def boot_os(guest):
        guest.cpm = target == 'cpm'
        first = guest.wait_for(r'(?:new date: *|A[>:])')
        if first.lower().endswith('date:'):
            guest.issue('', 'new time: *')
            guest.issue('', prompt)

    cfg_file.write_text(os_cfg)
    with DiskGuest(work) as guest:
        boot_os(guest)
        guest.issue('romxfer get demo out.bas', 'volume signature\\.\n' + prompt)
        guest.issue('romxfer init 320', 'Type YES:')
        guest.issue('yes', 'Done\\.\n' + prompt)
        guest.issue('mbasic86', 'Ok')
        guest.issue('10 print 37', '10 print 37')
        guest.issue('save "xfin.bas"', 'Ok')
        guest.issue('system', prompt)
        guest.issue('romxfer put xfin.bas demo', 'Done\\.\n' + prompt)

    cfg_file.write_text(cfg + '\ndisk { drive=0 type="auto" file="raw.img" }\n')
    with XT(work) as guest:
        guest.line('run "demo"')
        guest.expect(' 37')
        guest.line('10 print 729')
        guest.line('save "demo"')
        guest.expect('Ok')

    cfg_file.write_text(os_cfg)
    with DiskGuest(work) as guest:
        boot_os(guest)
        guest.issue('romxfer get demo xfout.bas', 'Done\\.\n' + prompt)
        guest.issue('romxfer get demo xfout.bas', 'already exists\\.\n' + prompt)
        guest.issue('mbasic86 xfout.bas', r' 729\nOk')
    print(f'PASS {target} native SAVE -> PUT -> ROM RUN/SAVE -> GET -> native RUN')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('config', type=Path)
    parser.add_argument('target', choices=['dos', 'cpm'])
    parser.add_argument('boot', type=Path)
    args = parser.parse_args()
    with tempfile.TemporaryDirectory() as tmp:
        test(args.config.resolve(), args.boot.resolve(), args.target, Path(tmp))
