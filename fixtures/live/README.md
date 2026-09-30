# Independent live-Figma fixtures

Source: FigmaMetal — Native Fidelity Lab (the original lab name), file `flxINzepb5BgRcRfGj0Tl5`, created for this project on 2026-09-29. These are conformance examples authored in real Figma, not a user's production animation.

- `conformance.source.json`: static frame `1:9`; original paths, transforms and paint values.
- `motion.source.json`: frame `2:8`, animated child `2:9`; original resolved and manual source tracks.
- `*.figmetal.json`: deterministic compiler outputs. Regenerate with `node scripts/compile_live.mjs`.

The compact snapshots omit only default-valued properties and unused empty metadata. Live fingerprints in `scripts/verify_source_fingerprints.mjs` check all 13 node path/transform sets and the source stroke outline. The shared capture module was also run in the live host and its temporary-node cleanup checked.

## Original reference files

This repository includes `conformance.reference.png` (600 × 420, independently exported by Figma) and `motion.reference.mp4` (320 × 180, 30 fps, 61 endpoint-inclusive Figma-rendered frames). They are test references only, not runtime assets.

These original files were omitted from the early source-only ZIP, but are included in the public repository so anyone can reproduce the comparison. Do not replace them with native Metal output. Re-exporting changed designs creates a new reference that needs explicit review.

Original SHA-256 values:

```text
d6bbc21f4cde9e95fc637f444b40693cf0332d7f533aafcc5ad5f4304786efa1  conformance.reference.png
ee1282e130965041a0f04959ece13a39cb7e9dc9e24d595e0c220df3e23d388e  motion.reference.mp4
```

With Xcode, Node, Pillow and ffmpeg/ffprobe available, run `./scripts/verify_live.sh`. It produces `artifacts/phase2/index.html` and machine-readable per-frame metrics. References and reports already exist on the Mac used for this run.
