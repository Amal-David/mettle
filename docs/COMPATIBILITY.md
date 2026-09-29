# Compatibility contract — v0.1

The code is authoritative. The following describes intentional boundaries, not blanket Figma support.

| Source feature | v0.1 handling |
|---|---|
| Shape/Boolean fill geometry | Source paths; Boolean operands are not independently drawn. |
| Bézier curves | Adaptive local-coordinate approximation; not pixel-identical Figma tessellation. |
| Holes and concave paths | Nonzero/even-odd native meshes. |
| SVG arc `A` command | Rejected. No silent line-segment replacement. |
| Solid / linear / radial paint | Native shader; ordinary alpha supported. |
| Diamond/angular gradients | Error. |
| Images, videos, patterns, shader fills | Error. |
| Normal/pass-through node blend | Ordinary source-over path; advanced backdrop behavior unverified. |
| Other blend modes | Error. |
| Frame clipsContent | Native child clipping using source fill geometry. |
| Sibling masks | Error. |
| Opacity | Native group isolation, including overlapping children. |
| Effects, blur, shadows, glass | Error; not recreated approximately. |
| Strokes | Temporary-copy outline adapter; live Figma conversion still requires validation. |
| Text | Temporary-copy vector outlines; missing fonts and mixed colors rejected. No font files included. |
| Independent regional paints | Error where detected. |
| Auto layout | Fixed export-size snapshot, not responsive runtime layout. |
| Translation / scale / rotation / opacity | Supported Motion bindings where exposed by the host. |
| Solid-color motion | Supported four-component effective-color tracks. |
| Cubic, linear, hold | Preserved as explicit track data. |
| Spring/back/unsupported named easing | Error, not replaced with ease-in-out. |
| Motion transform origin | Explicit center/top-left export choice and warning; source pivot parity unverified. |
| Independent nested timelines | Error. |
| Animated geometry / path trim / layout / text | Error. |
| A→B translation/opacity/solid color | Supported when hierarchy and geometry match. |
| A→B added/removed/reordered layers, morphs, resizing, rotation/skew/scale | Error. |
| Interactive prototype events | Not exported by the single-scene player; host owns events. |

## Strict versus partial

The plugin returns a report containing severity, code, node ID and message. An error blocks download by default. The native loader also rejects documents containing error diagnostics by default. Both sides require explicit opt-in for partial results (`--allow-partial` in the CLI).

Warnings still matter: an absent Motion API or an explicit pivot choice can require manual source verification even when there are no errors. "Exports successfully" is not a certification of pixel parity.

## Public source references used during implementation

- Figma Plugin API Motion: https://developers.figma.com/docs/plugins/api/Motion/
- Figma node fillGeometry: https://developers.figma.com/docs/plugins/api/VectorPath/
- Figma paint definitions: https://developers.figma.com/docs/plugins/api/Paint/
- Figma flatten API: https://developers.figma.com/docs/plugins/api/properties/figma-flatten/
- Apple Metal: https://developer.apple.com/metal/

The Motion API was documented as beta when this prototype was developed on 2026-09-29. Production compatibility should be rechecked against the running Figma host rather than inferred from static documentation alone.
