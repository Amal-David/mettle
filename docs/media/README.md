# README media provenance

These assets were generated for the September 30, 2026 Mettle publication. No invented UI result is presented as a screenshot.

The October 8 Community repair adds a separate evidence-backed walkthrough. It is generated from the pinned Figma reference PNGs and native CI archives; its presentation transitions move cards and labels only.

| Asset | Source |
| --- | --- |
| `hero.png` | Designed cover with typography and actual `native-frame.png` Metal output. Its framing is presentation artwork, not a Figma screenshot. |
| `native-preview.png` | Actual macOS window capture of `mettle demo --time 1`. Only the Mettle window was captured, with no desktop or unrelated content. |
| `native-frame.png` | PNG read back from the Metal renderer at t=1 s for the synthetic bundled scene. |
| `native-demo.gif` / `.mp4` | 120 evaluated native frames over four seconds from `examples/demo.figmetal.json`. Synthetic renderer-test artwork. GIF delivery is 20 fps; MP4 is 30 fps. Neither is a runtime input. |
| `fidelity.png` | Labeled, side-by-side composition of Figma's original 600×420 PNG and Mettle's rendering of the source snapshot. |
| `figma-vs-mettle.gif` | Matched-time pairs from the Figma video reference and Mettle output. The 30 fps H.264 reference is lossy; the GIF samples both sides at 20 fps. |
| `comparison.json` | Independent comparison measurements, including all 61 source-video frames. |
| `community-overview.png` | Static summary of the final Community verification: 12/12 accepted cases, 13 endpoints, and the explicitly retained blockers. |
| `community-walkthrough.gif` / `.mp4` | Ten-second presentation assembled from immutable Figma endpoint PNGs and the pinned Standard/High native evidence. It does not synthesize loader morphs or intermediate prototype playback. |
| `community-fidelity.png` | Detailed source/Standard/High/difference figure generated from the two pinned native CI archives. |

`../VERIFICATION.md` explains the corpus and limits. Glyph edge antialiasing differs; the images do not establish universal or pixel-perfect parity.

## Reproduce

On a Metal-capable Mac with Xcode, Node, Python/Pillow, and ffmpeg:

```bash
./scripts/render_readme_media.sh
```

For the app screenshot, launch `swift run -c release mettle demo --time 1`, then use macOS window screenshot capture. The app prints its window ID; `screencapture -x -o -l WINDOW_ID docs/media/native-preview.png` captures only that window using the machine owner's ordinary OS permissions.

Typography is rasterized from a local system font; font files are not included. Original references retain the checksums in `fixtures/live/README.md`. Never regenerate Figma reference files using Mettle output.

Rebuild the Community media from the checked archives with:

```bash
python3 scripts/render_community_evidence.py
python3 scripts/render_community_walkthrough.py
```

## Preview redesign — 2026-09-30

`preview-welcome.png` and `preview-references.png` are genuine captures of the redesigned Mettle native window. `preview-workspace.png`, when present, is an actual loaded-file view using a clearly labelled developer fixture. They replace the old showcase screenshot in the README; `native-preview.png` and `hero.png` document the earlier presentation and are not current UI.

External artwork visible in these new screenshots is credited in [reference attribution](../../Sources/MettlePreview/References/ATTRIBUTION.md) and remains CC BY 4.0, not MIT. No reference animation is claimed as Mettle output. See [usability audit](../UI_AUDIT.md).
