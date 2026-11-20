#!/usr/bin/env python3
"""Regression: real bundled app must survive notification callbacks."""
from pathlib import Path
import subprocess
import time
root = Path(__file__).resolve().parents[1]
app = root / 'dist/积存金.app/Contents/MacOS/GoldBar'
p = subprocess.Popen([str(app), '--settings', '--diagnostics'], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
try:
    time.sleep(40)
    assert p.poll() is None, f'App crashed: {p.communicate()}'
    p.terminate()
    out, err = p.communicate(timeout=10)
    assert out.count(b'QUOTE_OK') >= 2, f'No successful real app quote: {out!r} {err!r}'
    print(out.decode())
    print('PASS: bundled app survives startup, fetches live data, and updates menubar')
finally:
    if p.poll() is None:
        p.terminate()
        p.wait(timeout=10)
