# Independent live-Figma fixtures

Source: FigmaMetal — Native Fidelity Lab, file `flxINzepb5BgRcRfGj0Tl5`, created for this project on 2026-09-29. These are conformance examples authored in real Figma, not a user's production animation.

- `conformance.source.json`: static frame `1:9`; original paths, transforms and paint values.
- `motion.source.json`: frame `2:8`, animated child `2:9`; original resolved and manual source tracks.
- `*.figmetal.json`: deterministic compiler outputs. Regenerate with `node scripts/compile_live.mjs`.

The compact snapshots omit only default-valued properties and unused empty metadata. Live fingerprints in `scripts/verify_source_fingerprints.mjs` check all 13 node path/transform sets and the source stroke outline. The shared capture module was also run in the live host and its temporary-node cleanup checked.

## Original reference files

The installed Mac checkout contains `conformance.reference.png` (600 x 420 Figma PNG) and `motion.reference.mp4` (320 x 180, 30 fps, 61 endpoint-inclusive frames from Figma). They are test oracles only, not runtime assets. The downloadable source-only ZIP omits these binaries and the generated HTML visual report; native scene playback and ordinary source/GPU tests do not require them.

To run the full visual harness on another checkout, copy those two files from the installed Mac checkout into this folder. Otherwise independently re-export the unchanged source frames in Figma at the same settings, verify timing/dimensions, and explicitly review any new golden. Never create or replace these reference files with native Metal output.

Original SHA-256 values:

```text
d6bbc21f4cde9e95fc637f444b40693cf0332d7f533aafcc5ad5f4304786efa1  conformance.reference.png
ee1282e130965041a0f04959ece13a39cb7e9dc9e24d595e0c220df3e23d388e  motion.reference.mp4
```

With Xcode, Node, Pillow and ffmpeg/ffprobe available, run `./scripts/verify_live.sh`. It produces `artifacts/phase2/index.html` and machine-readable per-frame metrics. References and reports already exist on the Mac used for this run.
