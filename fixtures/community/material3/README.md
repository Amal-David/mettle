# Material 3 Community source corpus

These fixtures come from the **Material 3 Design Kit by Google / Material Design**, available through [Figma Community](https://www.figma.com/community/file/1035203688168086460/material-3-design-kit). They are exact published component instances captured on **2026-10-08**, with their original vector geometry, colors, hierarchy, and prototype reactions. Figma and Google's own documentation identify the kit and its author: [Figma UI kits](https://help.figma.com/hc/en-us/articles/24037724065943-Start-designing-with-UI-kits), [Google's account of maintaining the kit](https://design.google/library/figma-comments-material-ux-euphrates-dahout).

The import lives on an isolated [Community comparison page](https://www.figma.com/design/flxINzepb5BgRcRfGj0Tl5?node-id=18-2) in the existing Mettle lab. Each selected variant was instantiated at its natural size inside a separate transparent, unclipped host frame. The source artwork and interactions were not authored or changed for Mettle.

## What the corpus establishes

| Source family | Captured source | Compiler result | Independent reference coverage |
| --- | --- | --- | --- |
| Loading indicator | Seven genuine Smart Animate states and their directed timeout cycle | All seven static states compile; all seven changing-path transitions are explicitly blocked | Seven Figma endpoint PNGs, 48 × 48 |
| Switch | Selected, icon-free Enabled → Hovered states; genuine descendant `ON_HOVER` reaction | A 200 ms transition compiles with two paint bindings and no errors | Two Figma endpoint PNGs, 60 × 48 |
| Circular indeterminate progress | Wave, 4 dp, Step 1 | Static geometry compiles; no executable motion was observed in the inspected component set | One Figma PNG, 49 × 49 |
| Linear indeterminate progress | Flat, 4 dp, Step 1 | Static geometry compiles; no executable motion was observed in the inspected component set | One Figma PNG, 404 × 12 |

These are four component families from one creator's Community kit. They are not four independently authored motion projects. The two progress controls are useful static controls and examples of absent motion; a numbered variant is not sufficient evidence of an animation.

**Compilation acceptance is not native rendering parity.** The source capture stage had no Metal device. A later [native CI run and preserved report](../../../docs/COMMUNITY_VERIFICATION.md) passed all 12 render cases / 13 endpoint frames at High quality on an Apple Paravirtual device. The PNGs are static exports of actual variants, not frames sampled from a playing Figma prototype; the successful endpoint comparison does not verify intermediate playback. The corpus and runner distinguish `static`, `endpoint-states`, and `timeline-frames` coverage.

## Authentic motion evidence

The loading sequence follows **1 → 2 → 3 → 4 → 5 → 7 → 6 → 1**. Each source reaction is `AFTER_TIMEOUT` with a delay of `0.0010000000474974513` seconds and a `CHANGE_TO` / `SMART_ANIMATE` duration of `0.4000000059604645` seconds. The cubic easing is `(0.20000000298023224, 0, 0, 1)`. The exact values are retained in the snapshots and replay bundles. The resulting bounded clips have duration `0.40100000600796193` seconds, including the source delay; they do not implement the full prototype state machine.

The loader changes actual cubic path topology and size/clip geometry. Mettle emits `TRANSITION_DRAW_GEOMETRY` and `TRANSITION_GEOMETRY` errors for the unsupported changes. It does not relabel a static render or an invented dissolve as a successful animation. Figma's [Smart Animate documentation](https://help.figma.com/hc/en-us/articles/360039818874-Smart-animate-layers-between-frames) describes matching and fallback behavior, but no independent midpoint observation was available to establish the specific fallback used by this source. The loader remains blocked until its behavior can be implemented and verified against real source playback.

For the switch, the selected root is instance `24:199`, but the source hover interaction belongs to descendant `I24:199;54446:25292`, named `Target`. Its destination is source component `24:65`, represented by captured target instance `24:206`. Both exact source component identities are retained. The source duration is `0.20000000298023224` seconds, with no delay and the same cubic easing as above. The target also has a genuine `MOUSE_LEAVE` connection back to the enabled state, so the replay explicitly selects the enabled start state.

The switch keeps its source geometry stable. Its existing circular state layer gains a solid purple fill at 8% opacity, and the thumb color changes. Mettle admits the paint appearance by adding a transparent endpoint for that same source fill on the same source geometry, then interpolates the paint values. It does not add a replacement shape.

The inspected loading and switch hosts returned `{"nodes":[]}` from recursive `get_motion_context`; the exact requests and responses are saved in `motion-context.json`. These are prototype Smart Animate reactions, not native keyframe timelines. Their motion evidence comes from the captured reactions. The capture process did not add a native timeline or synthesize missing motion tracks.

## Reference bounds are part of the comparison

Reference PNGs are the unmodified bytes returned by `exportAsync({format: 'PNG', constraint: {type: 'SCALE', value: 1}})` on the source host frames. The document uses Figma's `LEGACY` color profile; the exported PNG metadata declares sRGB. The export defaults are `contentsOnly: true`, `useAbsoluteBounds: false`, and `colorProfile: 'DOCUMENT'`, as documented by Figma's [ExportSettings API](https://developers.figma.com/docs/plugins/api/ExportSettings/).

Figma exports unclipped overflow outside nominal component dimensions. The camera rectangle therefore must be explicit:

| Fixture | Nominal layout | Local reference viewport `(x, y, width, height)` |
| --- | --- | --- |
| Both switch states | 52 × 32 | `(0, -8, 60, 48)` |
| All loading states | 48 × 48 | `(0, 0, 48, 48)` |
| Circular wave | 48 × 48 | `(-0.08150482177734375, -0.0849151611328125, 49, 49)` |
| Linear flat | 404 × 12 | `(0, 0, 404, 12)` |

`source-bounds.json` preserves each root's original absolute transform, layout bounds, and render bounds. All these roots have identity linear transforms, allowing the render origin to be converted to local coordinates by subtracting the absolute translation. The camera preserves nominal geometry and translates the compiled root by `(-x, -y)`.

The two SVGs in `reference/` are additional, unmodified provider exports used only to inspect viewport mapping. They are not compiler input. The switch SVG places its track at `y=8` in a 60 × 48 viewport. The circular SVG's path coordinates support the fractional render origin; flooring it to `(-1,-1)` would shift the artwork. The PNG's observed 49 × 49 dimensions are preserved. Figma reports a tiny floating-point excess in the linear render width but exports 404 pixels; the comparison retains that actual dimension.

## Files and reproduction

`provenance.json` records the Community URL, creator, license attribution, library and variant keys, source instance/frame IDs, capture method, SHA-256 fingerprints, original PNG dimensions, export settings, camera mapping, and known coverage limits. Snapshot hashes and PNG hashes are checked before any compilation. Exact request timestamps were not reconstructed: reference metadata records the capture date and labels local file-save timestamps separately.

`*.snapshot.json` contains the exact captured instance hierarchy. The snapshot includes `sourceComponent` identity and root absolute bounds. Inside/outside stroke outlines, where required, came from Figma's own outlining API; temporary clones were removed and their IDs are recorded in the capture audit. No screenshots were traced into geometry.

`source/*.source.json` contains replayable `mettle-source` bundles for the eleven static states, the switch hover transition, and seven blocked loader transitions. `compiled/*.figmetal.json` contains the corresponding scene documents. Files named `*.blocked.figmetal.json` contain deliberate error diagnostics and are not accepted native animation exports. `compile-report.json` records each result, source timing, diagnostics, coverage, and output fingerprints. `corpus.json`, maintained by the comparison runner, binds the selected scene documents to their independent source references.

From the repository root:

```sh
node scripts/compile_community.mjs
node scripts/compile_community.mjs --check
```

The first command regenerates only source replay bundles, compiled documents, and the compilation report. It does not change the source snapshots or reference images. The second verifies the committed output bytes without writing. Both reject changed source fingerprints, mismatched reference dimensions, missing source transitions, fallback panel timing, unexpected compiler diagnostics, and a loader path change that silently stops producing its expected rejection. A newly supported loader requires independent source playback verification and an intentional update to the corpus contract.

The generic replay CLI can reproduce any accepted scene from its saved source bundle. The native comparison runner requires a Metal-capable macOS environment and must retain the coverage distinction above; endpoint references cannot be promoted to sampled timeline references.

## Attribution and license

**Material 3 Design Kit by Google / Material Design**, [original Community resource](https://www.figma.com/community/file/1035203688168086460/material-3-design-kit), design assets under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). These fixtures preserve the original source artwork and states; Mettle's compiled representation is an adaptation for testing. Google and Material Design do not endorse Mettle.

Figma's [Community licensing policy](https://help.figma.com/hc/en-us/articles/360042296374-Figma-Community-copyright-and-licensing) identifies CC BY 4.0 for free files, and Material's [resource overview](https://m3.material.io/get-started) identifies Apache 2.0 or CC BY 4.0 for its code and design resources. This attribution applies to the captured design assets and references. It does not change the license of Mettle's own implementation code.
