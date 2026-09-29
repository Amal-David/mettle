# FigmaMetal

**Experimental, source-based Figma → native Metal animation export.**

FigmaMetal exports structured paths, paints, transforms and supported motion tracks into an owned scene format, then renders them with a Swift + Metal runtime. It does not route through Lottie, Rive, Skia, a browser, a screenshot tracer, or an image/video sequence.

This is a working **v0.1 engineering prototype**, not a universal, pixel-perfect Figma player. Supported source features are translated deterministically. Unsupported features are reported; exports containing errors are blocked unless you explicitly allow an incomplete result.

```text
Figma selection
  └─ Development plugin: source geometry + motion + compatibility report
       └─ .figmetal.json (our scene data, not a third-party animation format)
            └─ Swift timeline evaluator + cached vector meshes
                 └─ Native Metal paint / mask / compositing passes
                      └─ MTKView on macOS or iOS
```

## Run the native demo

Requirements: a Metal-capable Mac, Xcode, Swift 5.9 or newer. Node 20+ is needed only to rebuild or test the exporter. The package declares macOS 13+ and iOS 16+ deployment targets; see [verification](docs/VERIFICATION.md) for the environments actually tested.

```bash
cd /path/to/figma-metal
swift run -c release figma-metal demo
```

The bundled demonstration is **synthetic renderer-test artwork**, not an animation captured from a real Figma file. It contains animated vector bars, gradient paths, clipping, an even-odd hole, nested transforms, and isolated group transparency. Use the preview's Play / Pause and scrub controls to inspect it.

```bash
# Render actual Metal output, not a software reconstruction.
swift run -c release figma-metal render --time 1 --output artifacts/frame.png

# Run CPU and, on a Mac, actual Metal GPU pixel tests.
swift test
(cd plugin && npm test)

# Synchronous offscreen benchmark. Not an iPhone frame-rate measurement.
swift run -c release figma-metal bench --frames 180
```

## Export from Figma

The ready-to-import development plugin is in `plugin/`. `code.js` is included; there is no npm installation step and no third-party JavaScript dependency.

1. In Figma Desktop, import `plugin/manifest.json` as a development plugin.
2. Select one frame/component, then run **FigmaMetal — Direct Metal Export**. Use **One selection — Motion / static scene** for supported source Motion tracks, or static artwork.
3. Inspect the report. Leave **Allow incomplete export** unchecked. Save the `.figmetal.json` file when export is permitted.
4. Preview that file with the native player:

```bash
swift run -c release figma-metal validate /path/to/scene.figmetal.json
swift run -c release figma-metal demo /path/to/scene.figmetal.json
```

For a bounded A→B animation, select **two** same-size frames and choose the two-frame mode. The plugin orders them left-to-right, matches uniquely named sibling layers within their hierarchy, and reads the first matching Smart Animate connection's duration/easing when available. Without such a connection, duration is explicitly taken from the panel. It does **not** recreate general navigation or a prototype's complete state machine.

The **Create A/B test frames in this file** button creates a small test pair in the current Figma file. It changes the file only when pressed. Geometry export itself does not flatten original text: it outlines temporary copies and removes them afterward.

The manifest contains a local development identifier. If Figma requests a Figma-assigned plugin ID, create a development plugin with **New Plugin**, copy its assigned `id` into this manifest, and re-import it. An assigned ID is required before publishing; this build does not publish anything.

Rebuild the plugin after changing its source:

```bash
(cd plugin && npm run build && npm run check && npm test)
```

**Live-host caveat:** automated exporter tests use Figma-shaped snapshots. The development plugin's live Figma API integration and fidelity on a user-authored Figma animation still need a real-file test. In particular, Motion API availability and pivot behavior must be checked in the actual host. See [compatibility](docs/COMPATIBILITY.md).

## What v0.1 implements

| Area | Implemented behavior |
|---|---|
| Vector geometry | Native SVG-style M/L/H/V/C/Q/S/T/Z path parsing, Bézier subdivision, concave fills, nonzero/even-odd holes, bounded self-intersection handling. Geometry is cached as GPU vertex buffers. |
| Paints | Solid colors and linear/radial gradients, including alpha. Multiple ordinary paints retain paint indices for animation. |
| Composition | Nested affine transforms, frame clipping, native offscreen group-opacity isolation, premultiplied-alpha blending, transparent output, up to 4× MSAA by default. |
| Motion | Explicit-time evaluation of translation, rotation, scale, opacity and solid-color tracks. Linear, hold and cubic Bézier easing; SET/OFFSET/SCALE track composition; once/loop/ping-pong. |
| Text / strokes | Plugin adapter outlines temporary source copies into vector geometry. Text is not editable or intrinsically accessible in the player. |
| Two-frame export | Restricted, same-topology transitions for translation, opacity and solid colors; rejects unsupported geometry changes rather than guessing a crossfade. |
| Integration | Swift Package libraries, SwiftUI Metal view, native macOS preview, source validator, GPU PNG export, benchmark, regression tests. |

Not yet implemented: arbitrary Figma shaders/effects, shadows/blur, image/video/pattern paints, advanced blending, sibling masks, animated path morph/trim, changing layout or text, nested independent timelines, spring easing, complete Smart Animate parity, prototype event handling, and native hit testing. Some text/vector regional-paint cases are rejected. This is deliberately a bounded renderer, not an entire application/UI framework.

## Embed in a SwiftUI application

Add this directory as a local Swift Package dependency in Xcode and link the `FigmaMetal` product. Add your exported JSON to the application's resources. Create the renderer once, not on every SwiftUI body evaluation.

```swift
import SwiftUI
import FigmaMetal

struct AnimationScreen: View {
    private let renderer: MetalRenderer

    init(sceneURL: URL) throws {
        let document = try SceneDocument.load(url: sceneURL)
        renderer = try MetalRenderer(scene: document.scenes[0])
    }

    var body: some View {
        FigmaMetalView(renderer: renderer)
            .aspectRatio(renderer.scene.width / renderer.scene.height,
                         contentMode: .fit)
            .accessibilityLabel("Animated illustration")
    }
}
```

Pass `time: someValue` to scrub deterministically, or leave `time` nil for playback. The view pauses for Reduce Motion and inactive scene phases. Keep meaningful labels, buttons, focus, interaction and navigation in native SwiftUI/UIKit controls outside the vector surface. Call a renderer from **one thread**; the provided host uses the main thread.

The shader source is packaged with the Swift target and compiled through Metal at renderer initialization. Export does not emit a unique `.metal` program per rectangle: it emits source scene data for the shared native shaders. This remains a direct native renderer, without a third-party animation compatibility ceiling.

## Project structure

```text
Sources/FigmaMetalCore/        Scene schema, time evaluator, parser, tessellator
Sources/FigmaMetal/            Metal renderer and SwiftUI host
Sources/FigmaMetal/Shaders/    Actual Metal Shading Language source
Sources/FigmaMetalDemo/        Native preview and command-line tools
plugin/src/compiler.mjs        Pure, testable source-data compiler
plugin/src/plugin.js           Figma host adapter
plugin/manifest.json           Import this into Figma Desktop
Tests/                        CPU and real-GPU regression tests
examples/                     Synthetic demo and compiler contract fixture
scripts/                      Verification and fixture utilities
```

## Boundaries and performance

This implementation prioritizes a testable direct path over engine-scale optimization. Béziers are approximated with an explicit local-coordinate tolerance, not Figma's private tessellator. The CPU tessellator has quadratic intersection work under bounded path budgets. Isolated groups and clips currently use full-target offscreen surfaces; they are correct for the tested cases, but expensive for deeply nested/high-resolution scenes. Draws are not aggressively batched. Color-space parity, especially Display P3 and difficult gradient boundaries, is not established.

The loader enforces a 32 MiB file limit and node/path/geometry bounds; the renderer limits target size and offscreen allocations. These checks are engineering guards, **not a security sandbox**. Only open trusted exported assets in this prototype. The plugin requests no network access; export does not upload the design to an external service.

Next engineering milestones and acceptance gates are in [architecture](docs/ARCHITECTURE.md). Actual test evidence and remaining validation gaps are in [verification](docs/VERIFICATION.md).

## License

MIT. FigmaMetal is an independent project and is not affiliated with or endorsed by Figma or Apple. The code license does not grant rights to any design, font, artwork or other material you export.
