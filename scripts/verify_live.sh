#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ "$(uname -s)" == Darwin ]] || { echo 'Live native comparison requires a Metal-capable Mac.' >&2; exit 2; }
command -v ffmpeg >/dev/null && command -v ffprobe >/dev/null || { echo 'Install ffmpeg (including ffprobe) first.' >&2; exit 2; }
python3 -c 'from PIL import Image' || { echo 'Install Pillow into your Python environment first.' >&2; exit 2; }
for file in fixtures/live/conformance.reference.png fixtures/live/motion.reference.mp4; do
  [[ -r "$file" ]] || { echo "Missing independent reference: $file. See fixtures/live/README.md; never substitute a native render." >&2; exit 2; }
done
[[ "$#" -le 1 ]] || { echo 'Usage: scripts/verify_live.sh [fresh-output-directory]' >&2; exit 2; }
mettle_live_output="${1:-artifacts/live/run-$(date -u +%Y%m%dT%H%M%SZ)}"
[[ ! -e "$mettle_live_output/motion-native" && ! -e "$mettle_live_output/styles/native" ]] || { echo 'Choose a fresh output directory to prevent stale-frame reuse.' >&2; exit 2; }
mkdir -p "$mettle_live_output"
node scripts/verify_source_fingerprints.mjs
node scripts/compile_live.mjs
node scripts/compile_motion_fixture.mjs
(cd plugin && npm run check && npm run build && npm test)
python3 scripts/test_compare.py
MTL_DEBUG_LAYER=1 swift test --jobs 4
swift run -c release mettle render fixtures/live/conformance.figmetal.json --time 0 --output "$mettle_live_output/native.png"
count=$(ffprobe -v error -select_streams v:0 -count_frames -show_entries stream=nb_read_frames -of csv=p=0 fixtures/live/motion.reference.mp4)
[[ "$count" =~ ^[0-9]+$ ]] || { echo 'Could not count Figma video frames.' >&2; exit 2; }
swift run -c release --skip-build mettle frames fixtures/live/motion.figmetal.json --fps 30 --frames "$count" --loop once --output "$mettle_live_output/motion-native"
python3 scripts/compare_live.py --native "$mettle_live_output/native.png" --frames "$mettle_live_output/motion-native" --output "$mettle_live_output"
swift run -c release --skip-build mettle frames fixtures/motion-2026/styles.figmetal.json --fps 10 --frames 21 --loop once --output "$mettle_live_output/styles/native"
python3 scripts/compare_style_motion.py --output "$mettle_live_output/styles"
printf '\nReport: %s/index.html\n' "$mettle_live_output"
