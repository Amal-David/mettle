# Mettle v0.2 verification

Verified on 2026-09-29 on the authorized Apple M4 Pro Mac. This phase validates a small live-Figma corpus, not arbitrary production designs or every supported feature.

## What ran

| Check | Result |
|---|---|
| Exporter and capture tests, including strict proxy and live fixtures | 36 passed |
| Swift core tests | 29 passed |
| Actual Metal GPU pixel/replay tests | 14 passed |
| Independent comparison-measurement tests | 5 passed |
| Total automated tests | **84 passed** |
| Metal API Validation | Enabled; test run passed without validation errors |
| Shared capture running in live Figma | 13 source-node geometry/transform fingerprints matched; stroke outline matched |
| Capture cleanup | All three temporary stroke nodes removed; top-level source nodes unchanged |
| arm64 iOS simulator library compilation | Passed; physical-device execution not performed |
| Independent visual regression gates | All six passed |

The source lab is FigmaMetal — Native Fidelity Lab, file `flxINzepb5BgRcRfGj0Tl5`. Static frame `1:9` is 600 x 420. Motion frame `2:8` is 320 x 180 and owns a two-second timeline. These frames were created for this project inside real Figma, rather than taken from a production file. The actual shared capture logic ran through the live Figma connector; this does not certify the desktop plugin panel/import workflow.

## Independent reference comparison

Figma supplied the reference PNG and 30-fps H264 MP4. The native renderer consumed only source JSON geometry, paints and tracks, never either reference. All 61 video frames, including the two-second endpoint, were compared at matching times.

| Measurement | Observed |
|---|---:|
| Static mean RGB absolute error, 0-255 levels | 0.241776 |
| Static mean alpha absolute error | 0.012631 |
| Static pixels with any channel error greater than 8 levels | 0.585714% |
| Interior probe maximum channel error | 1 level |
| Glyph-region mean RGB error | 3.893303 levels |
| Worst motion-frame mean RGB error | 1.130365 levels |
| Maximum detected motion bounding-box difference | 1 pixel |

Large flat backgrounds lower the global mean. Glyphs and curved edges have larger differences; the glyph region has 14.69% of pixels above an 8-level maximum-channel difference. This is **not pixel-perfect parity**. H264 is lossy, so video pixel errors include compression differences. Position is checked separately. Gates are engineering regression thresholds, not a general fidelity certification.

Verified cases: nonidentity linear/radial gradients, ordinary paint stacking, even-odd holes, group opacity with overlapping children, rounded frame clipping, rotated outside strokes, uniform Ag8 glyph paths, smoothed corners, and translation/opacity motion. The run did not test production typography breadth, Display P3, all stroke configurations, springs, source rotation/scale pivots, animation interruptions, nested independent timelines, or prototype interactions.

## Performance

A warmed synchronous offscreen benchmark of the live static 600 x 420 scene used 4x MSAA, 17 draws, 8,208 vertices and five surfaces. Across 600 measured frames on the M4 Pro, GPU median was **0.378 ms**, GPU P95 **0.496 ms**, wall-time median **0.564 ms**, and wall-time P95 **0.679 ms**. This is not startup latency, an iPhone benchmark, or a sustained on-screen frame-rate claim. The previous synthetic benchmark used different artwork; no speedup comparison is implied.

## Reproduce and inspect

On the installed Mac checkout:

```bash
cd /path/to/mettle
./scripts/verify_live.sh
open artifacts/phase2/index.html
```

The HTML report contains reference/native images, amplified differences, per-region measurements and representative motion pairs. `artifacts/phase2/comparison.json` records every frame. `full-verification.log`, `ios-build.log` and `benchmark.json` retain run evidence. The script counts actual reference frames rather than assuming a video excludes its endpoint. It fails if independent references are missing; it never substitutes native renders as goldens.

The original source-only ZIP omitted binary references. The public Mettle repository now includes the original Figma reference PNG/MP4 alongside the source data, so the full visual harness is reproducible after cloning. See `fixtures/live/README.md`. README media is output-only and is never loaded by the runtime.

The iOS cross-target build used `--build-system native`; Swift 6.4 reports that flag as deprecated. Older deployment-target operating systems, physical iPhones, thermal/energy behavior and hosted GitHub CI have not been exercised. This describes the original September 29 validation. On September 30 the code was rebranded as Mettle for public repository publication; see `docs/PUBLICATION.md` for that validation scope.
