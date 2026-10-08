#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

[[ "$(uname -s)" == Darwin ]] || { echo 'Community native comparison requires a Metal-capable Mac. Portable source checks: node scripts/compile_community.mjs --check && python3 scripts/compare_corpus.py --check-sources' >&2; exit 2; }
[[ "$#" -le 1 ]] || { echo 'Usage: scripts/verify_community.sh [fresh-output-directory]' >&2; exit 2; }
python3 -c 'from PIL import Image' || { echo 'Install Pillow in your Python environment first.' >&2; exit 2; }
output="${1:-artifacts/community/run-$(date -u +%Y%m%dT%H%M%SZ)}"
[[ ! -e "$output/native" ]] || { echo 'Native output already exists; choose a fresh output directory to prevent stale-frame reuse.' >&2; exit 2; }

# Check committed source-driven outputs. This never regenerates or blesses PNGs.
node scripts/compile_community.mjs --check
python3 scripts/compare_corpus.py --check-sources
python3 scripts/test_corpus_compare.py
MTL_DEBUG_LAYER=1 swift test --jobs 4
swift build -c release --product mettle
MTL_DEBUG_LAYER=1 python3 scripts/compare_corpus.py \
  --render-with .build/release/mettle \
  --raster-scale 2 \
  --native "$output/native" \
  --output "$output/report"
printf 'Community comparison report: %s/report/index.html\n' "$output"
