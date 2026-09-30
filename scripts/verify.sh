#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p artifacts
(cd plugin && npm run check && npm run build && npm test)
node scripts/generate_contract_fixture.mjs
node scripts/verify_source_fingerprints.mjs
node scripts/compile_live.mjs
swift test
swift run mettle validate examples/compiler-transition.figmetal.json
if [[ "$(uname -s)" == Darwin ]]; then
  swift run -c release mettle render examples/compiler-transition.figmetal.json --time 0 --output artifacts/contract-start.png
  swift run -c release mettle render examples/compiler-transition.figmetal.json --time 1 --output artifacts/contract-end.png
  swift run -c release mettle render --time 1 --output artifacts/demo-1.png
  swift run -c release mettle bench --frames 180 > artifacts/benchmark.json
fi
