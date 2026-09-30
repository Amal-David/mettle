#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
command -v ffmpeg >/dev/null
python3 -c 'from PIL import Image'
mkdir -p docs/media artifacts/publish
./scripts/verify_live.sh
swift run -c release mettle frames examples/demo.figmetal.json --fps 30 --frames 120 --output artifacts/publish/demo-frames
swift run -c release --skip-build mettle render --time 1 --output docs/media/native-frame.png
python3 scripts/render_readme_media.py
