"""Negative controls for make compare. Uses disposable fake guests, no build."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory() as tmp:
    work = Path(tmp)
    shutil.copy(ROOT/'Makefile', work)
    shutil.copytree(ROOT/'tools', work/'tools')
    (work/'ref').mkdir()
    (work/'build/dos').mkdir(parents=True)
    for folder in ('ref', 'build/dos'):
        (work/folder/'mbasic86.com').touch()
    (work/'case.txt').write_text('print 42\n')
    fake = work/'emu2'
    fake.write_text('''#!/usr/bin/env python3
import os, sys, tty
tty.setraw(0)
mode = os.environ['TEST_GUEST']
if mode == 'early':
    sys.exit(0)
for line in iter(lambda: sys.stdin.buffer.read(1), b''):
    buf = bytearray(line)
    while buf[-1:] != b'\\r':
        buf.extend(sys.stdin.buffer.read(1))
    sys.stdout.buffer.write(buf[:-1] + b'\\r\\n')
    if buf.startswith(b'print 42'):
        wrong = mode == 'wrong' and os.getcwd().endswith('/dos')
        print(43 if wrong else 42)
    elif buf.startswith(b'PRINT'):
        if mode == 'truncated':
            sys.exit(0)
        print('MBASIC-SESSION-COMPLETE')
    elif buf.startswith(b'SYSTEM'):
        sys.exit(9 if mode == 'failed' else 0)
    sys.stdout.flush()
''')
    fake.chmod(0o755)
    # Mixed deterministic numbers and dates must survive a bannerless run.
    sample = b'Ok\n12 Bytes free\n42\n01-02-2020\n10:20:30\n'
    assert subprocess.check_output([work/'tools/normout.sh'], input=sample) == sample
    for case in ('good', 'wrong', 'early', 'failed', 'truncated', 'missing'):
        env = dict(os.environ, PATH=str(work)+os.pathsep+os.environ['PATH'], TEST_GUEST=case)
        fixture = 'absent.txt' if case == 'missing' else 'case.txt'
        result = subprocess.run(['make', '-s', '-o', 'prog', 'compare', 'TESTS='+fixture],
                                cwd=work, env=env, capture_output=True, timeout=30)
        assert (result.returncode == 0) == (case == 'good'), (case, result)
        if case == 'wrong':
            assert b'< 42' in result.stdout and b'> 43' in result.stdout, result
        print('PASS', case)

    (work/'tests').mkdir()
    shutil.copy(work/'case.txt', work/'tests/case.txt')
    (work/'build/cpm').mkdir()
    (work/'build/cpm/mbasic86.cmd').touch()
    for target in ('parity-run', 'accept'):
        env = dict(os.environ, PATH=str(work)+os.pathsep+os.environ['PATH'], TEST_GUEST='failed')
        result = subprocess.run(['make', '-s', '-o', 'prog', target, 'TESTS=case.txt'],
                                cwd=work, env=env, capture_output=True, timeout=30)
        assert result.returncode != 0 and b'unsuccessfully' in result.stderr, (target, result)
        assert not (work/'tests/accept/dos/case.diff').exists()
        print('PASS failed runner propagates through', target)
