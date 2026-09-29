# Architecture and extension plan

## Why this is direct export

The export compiler consumes structured Figma geometry, not a screenshot. It writes an owned intermediate representation whose semantics can be extended alongside the renderer. This is a compiler IR, not a conversion into someone else's constrained animation ecosystem. Swift handles source parsing, tessellation, scene traversal and time evaluation; Metal handles vector rasterization, paints, masks and compositing. CoreGraphics/ImageIO appear in the CLI only to wrap already-rendered GPU pixels in a PNG.

A self-contained `.metal` file cannot supply an entire application's asset loading, state, animation clocks and resource management. This project's native output is deliberately a **scene package plus a reusable Swift/Metal runtime**. Future ahead-of-time native code generation can be added without changing the fundamental path.

## Source compiler

The plugin snapshots local fill geometry and affine transforms. Source children remain in rendering order; auto-layout geometry is resolved at export size. Paints retain their source indices rather than using draw indices as animation identifiers. Boolean operation children are not re-rendered after resolved parent geometry. Uniform text uses directly exposed source glyph paths when available. Strokes and fallback text are outlined on temporary copies, which are deleted in `finally` blocks. `capture.mjs` is shared by the plugin and live-host validation; it checks property capabilities before accessing proxy getters.

The pure compiler consumes the snapshot and produces draws, clip paths, per-node bindings and compatibility diagnostics. Unknown motion is retained under `sourceMotion` for future implementation, but is not executed. Unsupported motion/effects must not be replaced by fabricated easing, crossfades, screenshots or fake shader effects.

Motion beta getters may not exist in every host. A static design has no invented animation. Transform origin is an explicit export setting because the snapshot path does not establish a per-node source pivot; the report warns when rotation/scale depends on this choice. Independent timeline IDs are rejected until coordination is implemented.

## Native runtime

`FigmaMetalCore` is portable Swift. The parser subdivides curves at configurable tolerance. The tessellator splits scan bands at vertices and edge crossings, resolves winding intervals and emits non-overlapping trapezoid triangles within each path. It is a bounded prototype algorithm, not an optimal production tessellator.

`MetalRenderer` prepares meshes once and uploads them as native vertex buffers. Per-frame work evaluates bindings and traverses nodes. Shared Metal functions paint solids/gradients. A group with opacity below one is rendered to an isolated surface before alpha multiplication. Clips use a separately rendered alpha mask. Frame strokes render above children. Output and intermediate textures use premultiplied alpha.

Two frame-resource slots and a semaphore prevent CPU reuse before submitted GPU work finishes. Each slot pools offscreen textures. The renderer exposes explicit-time rendering for regression tests and screenshots, and command-buffer timing for offscreen benchmarks. It is single-caller-thread code, not a concurrently mutable actor.

## Phase 2 completed: a small independent live corpus

Two conformance frames were authored in real Figma, captured through the shared adapter, and rendered independently by Figma as PNG/video. The source snapshots retain geometry, transforms, paints and motion tracks. Source fingerprints confirm the transport did not alter paths/transforms. Goldens never enter the native runtime. The video check uses all 61 source timestamps, with position checks in addition to global RGB error. See VERIFICATION.md for results and limits.

This pass fixed reversed paint order, translation offset semantics, unsupported-proxy reads, and live-host text flatten failures. It reduced default curve tolerance to 0.05 source units and added deterministic replay and frame-sequence output. Full prototype interactions, effect passes, responsive layout and a production corpus were not implemented.

## Extension gates

1. **Real Figma corpus:** Export representative user files, capture reference timestamps, classify all diagnostics, and establish end-to-end pixel differences before claiming source fidelity. Verify text/stroke outline coordinate systems and nonidentity gradient transforms first.
2. **Motion fidelity:** Preserve authoritative per-node pivots, exact source easing, prototype interruption/state behavior, timeline cohorts and explicit unsupported cases. Add analytic spring parameters only when exposed, not guessed from a name.
3. **Effect passes:** Add a render graph for Gaussian/backdrop blur, shadows and supported blend modes, each with isolated source fixtures and goldens. WGSL/Figma shader adaptation is a separate future compiler/host project; no adapter is implemented here.
4. **Native interactions:** Add a state-machine/event layer, transform-aware hit testing and application input bindings without coupling them to rasterization. Keep accessibility semantics in native controls.
5. **Optimization:** Tight offscreen bounds, scissor intersections, batching, persistent uniforms, pipeline caches, tessellation caching and GPU captures. Establish stable color correctness before aggressive batching.
6. **Packaging:** Versioned backward compatibility, resource manifests, a production fuzzing suite, installable binaries and code-signing workflows. Public distribution/CI execution are not performed by this local build.

For each extension, add a compiler diagnostic test, CPU semantics tests where applicable, native GPU pixel tests, and a real Figma reference fixture. Removing an unsupported-feature error without those tests is not an implementation.

## Acceptance criteria for the next real-file pass

- No error diagnostics in the selected supported test animation.
- Source-node IDs and all animated source fields accounted for.
- Matching dimensions, transform origins and color-space settings documented.
- Reference/native frames compared at start, middle, end and transition interruption points.
- Transparent overlaps tested over both light and dark host backgrounds.
- No GPU validation errors or unbounded resource growth over repeated playback.
- Actual target iPhone/device thermal, memory and frame-time measurements; Mac offscreen results are not substituted.
