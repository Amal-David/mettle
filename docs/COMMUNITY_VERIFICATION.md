# Community source verification

## Current evidence — October 8, 2026

The corpus contains **11 authentic Material 3 component states**, **one compiled source hover transition**, and **seven deliberately blocked loading transitions**. Source provenance and deterministic compilation checks pass. Native Metal comparison of this new corpus is still pending; the capture session did not include a connected Metal-capable Mac.

The source is the [Material 3 Design Kit by Google / Material Design](https://www.figma.com/community/file/1035203688168086460/material-3-design-kit). Exact published component variants were imported into an isolated Figma page and captured through the Plugin API. The independent PNGs are Figma exports of those source variants. Their original bytes, node identities, component keys, source bounds, export settings, and SHA256 fingerprints are recorded in [provenance.json](../fixtures/community/material3/provenance.json).

| Cases | Source evidence | Compiler result | Native pixel status |
| --- | --- | --- | --- |
| Loading indicator, seven creator-authored states | Seven independent 48×48 PNGs and source snapshots | All seven static states compile | Pending |
| Circular wave, first state | Independent 49×49 PNG and source snapshot | Static state compiles | Pending |
| Linear progress, first state | Independent 404×12 PNG and source snapshot | Static state compiles | Pending |
| Switch enabled and hovered | Two independent 60×48 PNGs and source snapshots | Both static states compile | Pending |
| Switch enabled → hovered | Captured descendant `ON_HOVER` → `CHANGE_TO` Smart Animate reaction; source duration 0.20000000298023224 seconds | Two native color bindings; no blocking diagnostics | Endpoint comparisons pending; intermediate source playback not captured |
| Loading cycle `1 → 2 → 3 → 4 → 5 → 7 → 6 → 1` | Seven captured creator-authored `AFTER_TIMEOUT` connections | All seven reject animated clip/size or path changes with `TRANSITION_GEOMETRY` and `TRANSITION_DRAW_GEOMETRY` | Deliberately not rendered |

The switch reference images are **endpoint states**, not sampled prototype playback. Matching them can establish the final colors and geometry at the recorded endpoints. It cannot establish the easing curve or intermediate animation fidelity. The circular and linear snapshots contain no captured executable motion; numbered variants alone do not supply a timeline. These limits are preserved in the corpus and every HTML report.

## Reproduce on a Metal-capable Mac

Use Python 3.9 or newer with Pillow, Node.js, and the package's supported Swift/Xcode toolchain:

```bash
./scripts/verify_community.sh
```

An optional argument chooses a fresh output directory:

```bash
./scripts/verify_community.sh artifacts/community/my-native-run
```

The script checks the frozen source artifacts, runs the comparison measurement tests and Swift tests, builds the native CLI, renders only accepted cases, and writes a report. It refuses to reuse an existing native-output directory, preventing stale frames from contaminating a later run. Default outputs are under `artifacts/community/run-<UTC timestamp>/`:

- `native/<case-id>/manifest.json` and original native PNGs.
- `report/index.html`, linking a contact sheet for every case.
- `report/comparison.json`, containing all frame metrics, gates, source/native hashes, exact times, and declared blockers.

The renderer receives only compiled source JSON and explicit numerical settings. Reference PNG paths are never renderer arguments. For example, the source hover endpoints are rendered with `--times 0,0.20000000298023224 --loop once`; the explicit loop mode prevents the final endpoint from wrapping to the first frame.

Existing native outputs can be compared independently:

```bash
python3 scripts/compare_corpus.py \
  --native artifacts/community/my-native-run/native \
  --output artifacts/community/my-native-run/report
```

## Portable checks

These checks run without Metal. Their success establishes source integrity and measurement correctness, **not native rendering fidelity**:

```bash
node scripts/compile_community.mjs --check
python3 scripts/compare_corpus.py --check-sources
python3 scripts/test_corpus_compare.py
```

The initial harness run passes 22 adversarial tests. Their images and native-looking manifests are temporary, explicitly synthetic measurement fixtures. They are never added to the Community reference corpus or treated as GPU renders.

The complete local repair validation passed 105 JavaScript exporter/host tests and 27 Python measurement tests (22 Community harness tests plus five existing comparison tests). The Linux Swift run executed 64 tests: 63 passed and one explicitly skipped because Metal is unavailable. Apple-only code and actual GPU regressions need the Mac checks described above; the portable count does not include them as passes.

The tests exercise missing native output; incorrect document hash, device/backend, scene, duration, dimensions, loop, timestamps and frame indices; stale or missing PNGs; modified reference/source files; localized errors hidden by large backgrounds; invisible RGB values; out-of-bounds regions; endpoint exports relabeled as timeline samples; and preservation of original PNG bytes in the generated report. They also check that declared blockers cannot produce pixel success.

A comparison invoked against absent native files writes a reviewable report and exits with failure. It does not silently skip the accepted render cases. On the initial evidence-only run, the report records zero of 12 render cases compared, seven expected blockers, and `pixelPass: false`.

## Evidence contract

[corpus.json](../fixtures/community/material3/corpus.json) pins the source provenance, compilation report, replay bundles, compiled documents, source fixtures, viewports, schedules, regions, and measurement thresholds.

The harness validates the complete association:

1. The provenance file identifies the Community resource, capture file/date, component instances, source frames, snapshots, and independent PNGs.
2. Snapshot and PNG bytes match the provenance hashes. Reference dimensions and camera coordinates agree with the corpus.
3. Each replay bundle contains the exact captured nodes in their recorded source order and points to the pinned provenance.
4. Each compiled document points back to its replay-bundle hash. Its dimensions, scene index and duration match the case.
5. Each native manifest identifies `backend: Metal`, the exact compiled-document SHA256, scene index, duration, loop, device, dimensions, and one hash-checked PNG for each exact scheduled timestamp.
6. Native frame counts and indices are complete and ordered. Unlisted PNGs, duplicate filenames, missing endpoints, or a looping final frame fail verification.

The native frame schema is `mettle-frames`, version 1. Frame entries contain `index`, `time`, `file`, and `sha256`; the manifest additionally contains `sourceSHA256`, `sceneIndex`, `sceneDuration`, `loop`, `width`, `height`, and `device`.

For blocked cases, the exact set of error codes must match the declared contract. They receive the status `blocked-as-expected` and no pixel pass. Unexpected native output for a blocked case is itself a failed evidence check. `--check-sources` explicitly reports native pixels as `not-run`.

## Source camera boundaries matter

The independent PNG dimensions can exceed the nominal component dimensions. These source coordinate mappings are recorded in [source-bounds.json](../fixtures/community/material3/source-bounds.json) and checked by the compilation script:

| Source | Nominal size | Explicit source viewport |
| --- | --- | --- |
| Loading states | 48×48 | `x=0, y=0, width=48, height=48` |
| Switch states | 52×32 | `x=0, y=-8, width=60, height=48` |
| Circular wave | 48×48 | `x=-0.08150482177734375, y=-0.0849151611328125, width=49, height=49` |
| Linear progress | 404×12 | `x=0, y=0, width=404, height=12` |

The switch's overflow includes its interaction/state layer. The circular reference retains a fractional source origin verified against Figma's independent SVG export; flooring that origin would introduce an almost one-pixel camera shift. The linear PNG remains 404 pixels wide despite a small numerical excess in reported render bounds. No PNG is resized or cropped to make a comparison fit.

## Pixel measurements and initial gates

The harness reuses `compare_live.metrics`, which compares premultiplied RGBA. Fully transparent RGB values do not affect the result. Channel errors are expressed in 8-bit levels from 0 to 255.

Every frame must pass its own whole-image, foreground and regional gates. Errors are not averaged across frames or cases. Foreground measurements use the **union** of reference and native foreground, so missing or extra native geometry is included. The current transparent sources declare background RGBA `[0,0,0,0]` with an eight-level foreground threshold. An opaque-background corpus must declare its source background explicitly.

| Gate | Whole image | Foreground union | Every named region |
| --- | ---: | ---: | ---: |
| RGB mean absolute error | ≤2 | ≤4 | ≤4 |
| Alpha mean absolute error | ≤3 | ≤6 | ≤6 |
| Pixels with any channel error greater than 8 | ≤5% | ≤20% | ≤20% |

Foreground bounds may differ by at most two pixels. Regions include the switch thumb and hover halo, the loading shape, the two halves of the circular arc, and the visible four-pixel-high linear track. These measurements prevent large transparent areas from concealing missing artwork or a lost hover state.

These are **initial engineering gates declared before native Community measurements**. They are not a claim of measured quality or universal source compatibility. The harness never changes thresholds or promotes a native image into a reference. A failed gate requires inspecting the source/native/difference panels and the renderer or source coordinate mapping; any later threshold change must be separately justified and reviewed.

The HTML report copies the original reference and native PNG bytes into a separate directory, displays the exact timestamp, and adds a derived maximum-channel difference image amplified four times. Only that explicitly labeled difference image is synthesized.
