#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
command -v ffmpeg >/dev/null
python3 -c 'from PIL import Image'
[[ "$#" -le 1 ]] || { echo 'Usage: scripts/render_readme_media.sh [fresh-output-directory]' >&2; exit 2; }
mettle_media_output="${1:-artifacts/publish/run-$(date -u +%Y%m%dT%H%M%SZ)}"
[[ ! -e "$mettle_media_output" ]] || { echo 'Choose a fresh output directory so previous rendering evidence is preserved.' >&2; exit 2; }
mkdir -p docs/media "$mettle_media_output"
./scripts/verify_live.sh "$mettle_media_output/live"
swift run -c release mettle frames examples/demo.figmetal.json --fps 30 --frames 120 --output "$mettle_media_output/demo-frames"
swift run -c release --skip-build mettle render --time 1 --output "$mettle_media_output/native-frame.png"
python3 scripts/render_readme_media.py --run-directory "$mettle_media_output"
