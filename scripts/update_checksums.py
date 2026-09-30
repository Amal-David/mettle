#!/usr/bin/env python3
"""Refresh the tracked-file manifest. Stage intended files before running."""
from pathlib import Path
import hashlib
import subprocess
root = Path(__file__).resolve().parents[1]
paths = subprocess.check_output(['git', 'ls-files', '-z'], cwd=root).decode().split('\0')
lines = []
for name in sorted(filter(None, paths)):
    if name == 'SHA256SUMS':
        continue
    path = root / name
    if not path.is_file():
        raise SystemExit(f'Tracked file missing; stage deletions first: {name}')
    lines.append(f'{hashlib.sha256(path.read_bytes()).hexdigest()}  {name}\n')
(root / 'SHA256SUMS').write_text(''.join(lines))
print(f'Updated SHA256SUMS for {len(lines)} tracked files.')
