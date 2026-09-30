<p align="center">
  <img src="docs/media/hero.png" alt="Mettle — Design in Figma. Move in Metal. Experimental native animation compiler and renderer." width="1280">
</p>

# Mettle

**Design in Figma. Move in Metal.**

[![Source checks](https://github.com/Amal-David/mettle/actions/workflows/test.yml/badge.svg)](https://github.com/Amal-David/mettle/actions/workflows/test.yml)
![Status: experimental](https://img.shields.io/badge/status-experimental-e8b86d)
[![MIT license](https://img.shields.io/badge/license-MIT-7cd9c1)](LICENSE)

> [!WARNING]
> **Experimental v0.2.** A working renderer for a defined subset of Figma, not a drop-in player for every design or prototype. APIs and the asset schema may change. Do not depend on it for production yet.

Mettle reads the original paths, paints, transforms, and supported animation tracks from Figma and renders them with Swift and Metal. No Lottie conversion. No browser. No tracing screenshots and hoping the geometry matches.

```text
Figma source → Mettle exporter → scene + animation data → Swift evaluator → Metal
```

The exporter and renderer belong to the same project. A feature is limited by what we implement and verify, not by a third-party animation format. There is no Skia or Rive dependency either.

## See it run

![Animated vector test scene rendered directly by the native Metal backend](docs/media/native-demo.gif)

*Actual Metal output, recorded from a synthetic vector test scene. This GIF demonstrates the renderer; it is not an imported Figma production design, and the runtime does not play image sequences.*

<details>
<summary>Native macOS preview and a frame-by-frame Figma comparison</summary>

![Actual Mettle macOS preview window, including playback controls and scene information](docs/media/native-preview.png)

*An actual screenshot of the native app, not a UI mockup.*

![Figma-rendered reference compared with Mettle across the same motion timeline](docs/media/figma-vs-mettle.gif)

*Left: Figma's video export. Right: native Metal output from the source tracks. Both use the same timestamps; the Figma video is lossy.*

</details>

## Try the native demo

You need a **Metal-capable Mac and full Xcode**. The package uses Swift tools 5.9+ and declares macOS 13+ / iOS 16+ targets. Older deployment targets and physical iPhones have not been validated. [Test environments →](docs/VERIFICATION.md)

```bash
git clone https://github.com/Amal-David/mettle.git
cd mettle
swift run -c release mettle demo
```

Play, pause, and scrub in the preview. To open the animation captured from live Figma:

```bash
swift run -c release mettle demo fixtures/live/motion.figmetal.json
```

## Export your own scene

The development plugin is in [`plugin/`](plugin). Its built `code.js` is checked in, so **there is no npm install step**.

1. In Figma Desktop, import `plugin/manifest.json` as a development plugin.
2. Select a frame or component and run **Mettle — Experimental Metal Export**.
3. Choose the single-selection mode, inspect the compatibility report, and save the scene. Leave **Allow incomplete export** unchecked.
4. Validate and play it:

```bash
swift run -c release mettle validate path/to/scene.figmetal.json
swift run -c release mettle demo path/to/scene.figmetal.json
```

For a bounded A→B animation, select two same-size frames and choose the two-frame mode. It matches uniquely named siblings through the hierarchy and can read a matching Smart Animate connection's timing. It does **not** reproduce an application's navigation or interaction state machine.

The manifest uses a local development ID. If Figma asks for an assigned ID, create a development plugin through **New Plugin** and copy its ID into the manifest. This is not a published Figma Community plugin. The shared capture code has run in live Figma; the complete desktop import/panel workflow is still a separate validation gap.

The `.figmetal.json` extension and `figma-metal` format signature are retained from the original prototype so older scenes continue to load. They are Mettle's own data format, not an external runtime dependency.

## Use it in SwiftUI

Add this repository as a Swift Package dependency and link the **`Mettle`** product. Until there is a stable release, use `main` or pin a reviewed commit. Add the exported JSON to your app's resources and create the renderer once rather than in each `body` evaluation.

```swift
import SwiftUI
import Mettle

struct AnimationScreen: View {
    private let renderer: MetalRenderer

    init(sceneURL: URL) throws {
        let document = try SceneDocument.load(url: sceneURL)
        renderer = try MetalRenderer(scene: document.scenes[0])
    }

    var body: some View {
        MettleView(renderer: renderer)
            .aspectRatio(renderer.scene.width / renderer.scene.height,
                         contentMode: .fit)
            .accessibilityLabel("Animated illustration")
    }
}
```

Pass `time:` for deterministic seeking or leave it `nil` for playback. The view respects Reduce Motion and inactive scene phases. Keep labels, focus, buttons, and navigation in native SwiftUI/UIKit controls; the vector canvas is not an accessible UI framework. Use each renderer from one thread.

## What works, and what does not

| Area | Current implementation |
| :--- | :--- |
| Geometry | Bézier paths, concave fills, nonzero/even-odd holes, source corner geometry, bounded self-intersections. Cached GPU meshes. |
| Paint | Solid fills, linear/radial gradients, paint alpha, verified ordinary paint stacking. |
| Composition | Nested affine transforms, rounded frame clipping, isolated group opacity, transparent output, up to 4× MSAA. |
| Animation | Translation, rotation, scale, opacity, and solid-color tracks; linear/hold/cubic Bézier easing; deterministic evaluation and looping. **Source rotation/scale pivot parity remains unverified.** |
| Text and strokes | Uniform glyph paths exposed by Figma; temporary-copy outline fallback. Text is not editable, searchable, or intrinsically accessible in the runtime. |
| Tools | Figma exporter, Swift Package, SwiftUI view, macOS preview, validator, PNG/sequence export, benchmark, regression harness. |

**Not implemented:** arbitrary Figma shaders, blur/shadows, image/video/pattern paints, advanced blending, sibling masks, path morph/trim, spring easing, changing text/layout, independent nested timelines, general prototype events, or hit testing. Some regional-paint cases are rejected. [Full compatibility notes →](docs/COMPATIBILITY.md)

Exports with unsupported features are blocked by default. An explicit incomplete-export override exists for investigation, not as a promise of fidelity.

## Compared against Figma, not against ourselves

![Live Figma conformance reference beside Mettle's native rendering](docs/media/fidelity.png)

The test artwork was created **inside live Figma**. The capture implementation preserved its actual geometry, and independent Figma PNG/video exports supplied the references. Those images are never input to the native renderer.

On the small current corpus: static mean RGB error was **0.242 / 255**, and the largest detected boundary difference across **61 motion frames** was **1 pixel**. This is not pixel-perfect parity: curved edges and small text differ, the glyph-region mean error was **3.893 / 255**, and flat backgrounds lower the overall average. These are conformance fixtures, not a production-design benchmark.

**85 tests pass on the development M4 Pro**: 36 exporter/capture, 29 Swift core, 14 actual GPU, 1 preview-host regression, and 5 comparison-measurement tests. Metal API Validation and an arm64 iOS simulator library build also passed. Hosted CI checks source/compiler/core behavior and compilation; it does not claim GPU fidelity.

[Verification and remaining gaps](docs/VERIFICATION.md) · [Machine-readable comparison](docs/media/comparison.json) · [Media provenance](docs/media/README.md)

## Build, test, and reproduce

Node 20+ rebuilds the dependency-free exporter. The complete visual harness additionally needs Python 3 with Pillow and `ffmpeg` / `ffprobe`. Independent reference PNG/MP4 files are included in this repository.

```bash
(cd plugin && npm run build && npm run check && npm test)
swift test                       # Includes real GPU tests on a Metal-capable Mac.
./scripts/verify_live.sh          # Full source-to-Metal comparison against Figma.
open artifacts/phase2/index.html
```

```bash
# Native GPU output at an exact time.
swift run -c release mettle render --time 1 --output artifacts/frame.png

# Record the output; the runtime still evaluates vector geometry every frame.
swift run -c release mettle frames examples/demo.figmetal.json \
  --fps 30 --frames 120 --output artifacts/frames

# Offscreen timing; not an iPhone FPS or startup-latency measurement.
swift run -c release mettle bench --frames 180
```

```text
Sources/MettleCore/      Scene schema, animation evaluator, path parser, tessellator
Sources/Mettle/          Native renderer, Metal shaders, SwiftUI host
Sources/MettleDemo/      macOS preview and CLI
plugin/src/             Figma capture, compiler, panel adapter
Tests/                  Core and actual-GPU tests
fixtures/live/          Original Figma source data and independent references
scripts/                Capture checks, comparison harness, media generation
```

The renderer uses shared Metal shaders, not a different generated shader for every rectangle. Curve subdivision has a finite tolerance. Intersection work is bounded but quadratic; isolated groups use full-target surfaces. Large or deeply nested scenes need more optimization. Display P3, thermal behavior, and broad production fidelity remain unverified.

Only open **trusted exports**. File/geometry/allocation limits are safeguards, not a security sandbox. The plugin requests no network access and does not upload designs. No font files are bundled.

## Contributing

The most useful contribution is a small failing design plus an independent reference, followed by a regression test. Please do not replace Figma goldens with Mettle output to make a test pass. See [CONTRIBUTING.md](CONTRIBUTING.md), the [architecture notes](docs/ARCHITECTURE.md), and [security guidance](SECURITY.md).

Next validation work: production-file coverage, text/edge antialiasing, source rotation/scale pivots, physical-device playback, then additional effects. Nothing in that list is a shipped feature.

## License

[MIT](LICENSE). Mettle is independent and is not affiliated with or endorsed by Figma or Apple. The code license does not grant rights to designs, fonts, or other assets you export.
