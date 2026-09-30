#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ "$(uname -s)" == Darwin ]] || { echo 'Live native comparison requires a Metal-capable Mac.' >&2; exit 2; }
command -v ffmpeg >/dev/null && command -v ffprobe >/dev/null || { echo 'Install ffmpeg (including ffprobe) first.' >&2; exit 2; }
python3 -c 'from PIL import Image' || { echo 'Install Pillow into your Python environment first.' >&2; exit 2; }
for file in fixtures/live/conformance.reference.png fixtures/live/motion.reference.mp4; do
  [[ -r "$file" ]] || { echo "Missing independent reference: $file. See fixtures/live/README.md; never substitute a native render." >&2; exit 2; }
done
mkdir -p artifacts/phase2
node scripts/verify_source_fingerprints.mjs
node scripts/compile_live.mjs
node scripts/compile_motion_fixture.mjs
(cd plugin && npm run check && npm run build && npm test)
python3 scripts/test_compare.py
MTL_DEBUG_LAYER=1 swift test --jobs 4
swift run -c release mettle render fixtures/live/conformance.figmetal.json --time 0 --output artifacts/phase2/native.png
count=$(ffprobe -v error -select_streams v:0 -count_frames -show_entries stream=nb_read_frames -of csv=p=0 fixtures/live/motion.reference.mp4)
[[ "$count" =~ ^[0-9]+$ ]] || { echo 'Could not count Figma video frames.' >&2; exit 2; }
swift run -c release --skip-build mettle frames fixtures/live/motion.figmetal.json --fps 30 --frames "$count" --output artifacts/phase2/motion-native
python3 scripts/compare_live.py
swift run -c release --skip-build mettle frames fixtures/motion-2026/styles.figmetal.json --fps 10 --frames 21 --output artifacts/motion-2026/native
python3 scripts/compare_style_motion.py
printf '\nReport: %s/artifacts/phase2/index.html\n' "$PWD"
