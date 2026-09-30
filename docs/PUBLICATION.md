# Mettle publication validation

Publication preparation: September 30, 2026. The source began as the local FigmaMetal v0.1/v0.2 prototype. Both original implementation commits are retained in history.

## Changes for the public repository

- Renamed Swift products/modules to `Mettle` and `MettleCore`, the executable to `mettle`, and the SwiftUI component to `MettleView`.
- Rebranded the development exporter and native preview as experimental.
- Kept the `figma-metal` document signature and `.figmetal.json` extension compatible with existing scenes. Exporter metadata now uses Mettle.
- Added a real native screenshot, native-output GIF/MP4, and independent Figma comparison media, with reproducible scripts and provenance.
- Fixed an initial paused-preview blank frame: a controlled Metal view requests a redraw after the drawable resizes. Added a regression test for that lifecycle event.
- Included the original independent Figma PNG/video references. They were excluded only from the earlier source-only ZIP.
- Split hosted source/core/build CI from real-device GPU validation. A green source-check badge is not a GPU fidelity claim.

## Validation scope

The publication checkout is checked with the live comparison harness plus the paused-preview regression: 36 exporter/capture, 29 core, 14 Metal GPU, 1 preview-host, and 5 comparison-measurement tests (85 total). The full Swift suite runs with Metal API Validation on the M4 Pro. The iOS simulator library is cross-compiled; physical iPhone playback remains unverified.

The original comparison and benchmark are in `VERIFICATION.md`; `media/comparison.json` contains rerun per-frame results. Original reference hashes remain unchanged. This rebrand does not enlarge the verified Figma feature set.

The native preview is a developer inspector. Play restarts its timeline at the end; the underlying library retains the scene's own loop semantics. The synthetic demo is not a captured production animation.
