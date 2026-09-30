# Contributing to Mettle

Mettle is experimental. Small, reproducible changes are more useful than broad feature claims.

## Before changing the renderer

Read `docs/ARCHITECTURE.md` and `docs/COMPATIBILITY.md`. Keep unsupported features explicit. Do not introduce screenshot tracing, unreported raster fallbacks, or another animation-format runtime into the direct pipeline.

Include a focused regression test, the supported scope, and remaining edge cases. For a visual fix, use independently exported Figma references at matched sizes and timestamps. Never regenerate a golden using Mettle itself.

## Local checks

```bash
(cd plugin && npm run check && npm run build && npm test)
python3 scripts/test_compare.py
swift test --jobs 4
./scripts/verify_live.sh
```

The GPU suites require a Metal-capable Mac. A missing device is an error, not a silently skipped success. Public hosted CI separately checks source/compiler/core behavior and native compilation. Do not describe a green hosted run as GPU validation.

Commit `plugin/code.js` after changing plugin sources. Run `python3 scripts/update_checksums.py` after staging all intended changes. Keep `artifacts/`, build output, virtual environments, credentials, and fonts out of commits.

## Reporting a problem

Include the commit, macOS/Xcode/device versions, exact command, expected result, observed result, and a minimal source scene. Attach original reference images only when you own the right to share them. Remove private text, client artwork, asset tokens, and unrelated Figma metadata.

Do not upload secrets or sensitive designs to a public issue. See `SECURITY.md` for security reports.
