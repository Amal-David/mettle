# Verification record — 2026-09-29

This record distinguishes actual execution from implementation claims. No real Figma design has been used as a visual ground truth yet.

## Executed checks

| Check | Environment | Result |
|---|---|---|
| Core Swift regression suite | Apple M4 Pro, macOS 27, Xcode / Swift 6.4 | 29 passed, 0 failed |
| Actual Metal GPU pixel suite | Same physical Mac and GPU | 9 passed, 0 failed; not simulated or skipped |
| JavaScript compiler / host-adapter suite | Node 22.22.3 on the Mac and Node 22.16 on Linux | 25 passed, 0 failed (21 compiler + 4 mocked host tests) |
| Native iOS library compilation | Xcode iOS simulator SDK, arm64, iOS 16 deployment target | Passed; compilation only, not an iPhone runtime test |
| Release Metal image rendering | M4 Pro; bundled synthetic scene at 0, 1 and 2 seconds | PNGs produced; frame at 1 second visually inspected |
| Compiler → decoder contract | Synthetic source snapshots → JavaScript compiler → Swift loader / tessellator | Validated: 2 nodes, 2 animation bindings, 6 mesh vertices, 1-second clip; start/end PNGs also rendered on the M4 Pro |
| Portable Swift core | Swift 6.2.1, Linux | 29 core tests passed; Metal unavailable and explicitly skipped on Linux |

The native GPU suite checks device availability, BGRA channel order and transparent background, overlapping group opacity, child clip masks, a genuinely transparent even-odd hole, timeline-driven geometry translation, linear-gradient endpoints, transformed clipping, and repeat-frame stability.

The compiler suite covers source transforms, diagnostics, motion tracks, easing, topology restrictions, source-preserving transitions and unsupported-feature rejection. Four host tests execute the adapter inside a mocked Figma environment; they are **not** evidence of a live Figma integration test.

## Actual warmed Metal benchmark

Source: `artifacts/benchmark.json` generated on the connected Mac using:

```bash
swift run -c release --skip-build figma-metal bench --frames 180
```

| Measurement | Observed value |
|---|---:|
| GPU | Apple M4 Pro |
| Target | 720 × 480 pixels |
| Multisampling | 4× MSAA |
| Prepared vertices | 2,232 |
| Draw calls, final frame | 26 |
| Surface count, final frame | 3 |
| Timed frames | 180 |
| GPU median | 0.872 ms |
| GPU 95th percentile | 1.355 ms |
| CPU + submission + GPU wait median | 1.528 ms |
| CPU + submission + GPU wait 95th percentile | 2.127 ms |

The benchmark uses five warm-up frames, followed by synchronous offscreen rendering. It does not measure compositor scheduling, display presentation, an actual Figma export, iPhone performance, power consumption or battery life. CPU wall time excludes scene loading, initial tessellation and renderer/shader initialization. Cold-start GPU renders were materially slower: the first separate PNG render reported approximately 44.5 ms GPU time. Do not advertise the warmed number as startup latency or derive an on-screen FPS claim from it.

## Reproduce

```bash
bash scripts/verify.sh
```

For iOS simulator compilation with the tested Swift toolchain:

```bash
swift build --build-system native --scratch-path .build-ios \
  --target FigmaMetal --triple arm64-apple-ios16.0-simulator \
  --sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" --jobs 4
```

The tested Swift 6.4 toolchain warns that `--build-system native` is deprecated. This flag was used for the cross-target build; normal macOS tests used the default build system. The package's declared older deployment targets were not separately exercised on older operating systems.

Mac test/build logs and rendered images are retained under the installed project's `artifacts/` directory. They are ignored by Git. The source distribution includes the benchmark values in `docs/benchmark-m4-pro.json`; generated binaries and large build caches are not distributed.

## Remaining validation gates

1. Import the development plugin in a live Figma host and export its A/B test pair. Confirm the actual API shapes, text/stroke outlining and cleanup, and the assigned-plugin-ID requirements.
2. Export a real user-authored animation. Compare native frames to Figma captures at fixed timestamps and identical sizes, including pivots, gradients, clipping and group transparency. No pixel-perfect parity claim is justified before this.
3. Run the runtime on physical iPhones. Measure cold start, sustained frame time, memory and energy, including scene resize and app backgrounding.
4. Extend the bounded compatibility matrix only with source fixtures and regression tests. Hosted CI configuration is included but has not been run on GitHub.

A compiling project and passing synthetic tests demonstrate a working native foundation; they do not establish universal Figma compatibility.
