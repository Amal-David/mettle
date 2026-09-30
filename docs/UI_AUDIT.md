# Preview usability audit — 2026-09-30

## What was wrong

The original window presented a synthetic rendering fixture as the product. Its decorative bar and pill resembled controls, the real transport was barely labelled, and GPU metrics occupied permanent prime space. There was no visible route to open a user's export. A giant branded header repeated marketing copy while the actual workflow remained unclear. Test artwork was also being used as a design reference in the README.

## What changed

| Finding | Implemented correction |
|---|---|
| No obvious first action | The app opens a welcome screen with Open animation, file-drop support and a short export-to-preview guide. No test file is automatically opened. |
| Diagnostic art looked like UI | The original examples are only under Developer fixtures. Loaded test files are explicitly labelled. |
| Weak reference material | A separate Motion references gallery links four credited creator-made works. They are external inspiration, not rendered or imported by Mettle. |
| Engineering information dominates | File details are opt-in; device, vertex count and antialiasing live inside a collapsed Rendering details section. |
| Unclear transport | Play/Pause has a text label, Restart is separate, and speed, repeat, exact time, zoom and preview background are available. |
| Scrubbing and loop endpoints conflict | A deterministic transport clock owns playback; the native preview renders the exact seek endpoint. Speed changes and pause/resume preserve continuity. |
| No useful output action | Export frame opens a native save panel and writes the current frame at original canvas size with transparency. |
| Invalid files destroy context | Asynchronous loading retains the current file on errors and discards obsolete load results. |
| Forced dark showcase styling | Light presentation with an explicit Light/Dark/System choice; native controls and restrained hierarchy. |
| README leads with diagnostic artwork | The opening screenshot now shows the import workflow. Technical fixture images are collapsed and labelled as regression evidence. |

The renderer itself has not gained new animation/effect support in this change. The preview is an optional Mac utility, not a required part of iOS integration.

## Reference choices and licensing

See [Motion references](REFERENCES.md). Four original thumbnails are displayed proportionally, with attribution and CC BY 4.0 license information. They are not covered by the MIT code license. Watch original opens the credited creator page. The separate browser board loads official Rive interactive embeds on click; no Rive runtime is added to Mettle's native renderer.

Some creator preview MP4s are only still or very short states. For that reason the reference board links the actual interactive work instead of presenting thumbnail videos as complete animations.

## Verification

- **106 automated tests passed locally**: 36 exporter/capture, 29 core, 14 actual GPU, 1 renderer-host, 21 new preview/playback/reference, 5 comparison-measurement.
- Metal API Validation enabled; independent live-Figma visual regression gates passed.
- The `Mettle` library compiled for arm64 iOS simulator after adding the Mac-only preview target.
- Genuine window screenshots were inspected. The initial welcome headline was found to truncate and was corrected before the final screenshots.
- Accessibility inspection confirmed labelled controls, the reference gallery, developer-fixture selection and the native Open/Cancel panel. A direct Play action advanced the two-second test scene to its endpoint; reliable automated pause/scrub and keyboard interaction was not established, so those behaviors are covered by the model tests rather than claimed as complete UI automation. Additional model tests cover transport, loading failure preservation, static scenes, Reduce Motion and actual PNG export.

Screenshots are actual native app captures, not composited UI mockups. The loaded-file inspection uses a labelled regression fixture, not a new production animation. Automated model/GPU checks are not a substitute for testing every native file-panel, drag/drop, keyboard or display configuration. The full Figma Desktop plugin import/panel workflow and physical-iPhone execution remain unverified.

## Run

```bash
swift run -c release mettle preview
```

See [local installation](LOCAL_SETUP.md) for the exporter and optional Mac app. Community publication is deliberately deferred; see [distribution](DISTRIBUTION.md).
