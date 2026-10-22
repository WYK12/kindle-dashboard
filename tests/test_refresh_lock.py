"""Exercise the actual shell lock and queued manual requests, without a device."""
from pathlib import Path
import os
import subprocess
import tempfile
import time

root = Path(__file__).resolve().parents[1]
source = root / ('current' if (root / 'current').exists() else 'src') / 'mydash_v2/refresh.sh'
with tempfile.TemporaryDirectory() as folder:
    tmp = Path(folder)
    base = tmp / 'app'
    base.mkdir()
    fake = tmp / 'luajit'
    fake.write_text('#!/bin/sh\nprintf "%s\\n" "$2" >> "$CALLS"\nsleep 0.2\n')
    fake.chmod(0o755)
    script = tmp / 'refresh.sh'
    script.write_text(source.read_text().replace('/mnt/us/mydash_v2', str(base))
                      .replace('/mnt/us/koreader/luajit', str(fake))
                      .replace('/tmp/mydash-v2-refresh', str(tmp / 'lock')))
    env = dict(os.environ, CALLS=str(tmp / 'calls'))
    first = subprocess.Popen(['sh', str(script), 'auto'], env=env)
    deadline = time.monotonic() + 3
    while not (tmp / 'calls').exists():
        assert time.monotonic() < deadline
        time.sleep(0.01)
    for mode in ['weather', 'markets']:
        subprocess.run(['sh', str(script), mode], env=env, check=True)
    assert first.wait(timeout=5) == 0
    assert (tmp / 'calls').read_text().splitlines() == ['auto', 'auto,weather,markets']
    assert not (tmp / 'lock').exists()
    assert not list(tmp.glob('lock-request.*'))
print('PASS: one batch worker, queued manual requests, request coalescing and lock cleanup')
