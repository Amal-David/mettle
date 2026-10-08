#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p artifacts
(cd plugin && npm run check && npm run build && npm test)
node scripts/generate_contract_fixture.mjs
node scripts/verify_source_fingerprints.mjs
node scripts/compile_live.mjs
node scripts/compile_motion_fixture.mjs
node scripts/compile_community.mjs --check
python3 scripts/test_compare.py
python3 scripts/test_corpus_compare.py
python3 scripts/compare_corpus.py --check-sources
swift test
swift run mettle validate examples/compiler-transition.figmetal.json
swift run mettle validate fixtures/community/material3/compiled/switch-hover.figmetal.json
if [[ "$(uname -s)" == Darwin ]]; then
  swift run -c release mettle render examples/compiler-transition.figmetal.json --time 0 --output artifacts/contract-start.png
  swift run -c release mettle render examples/compiler-transition.figmetal.json --time 1 --output artifacts/contract-end.png
  swift run -c release mettle render --time 1 --output artifacts/demo-1.png
  swift run -c release mettle bench --frames 180 > artifacts/benchmark.json
fi
