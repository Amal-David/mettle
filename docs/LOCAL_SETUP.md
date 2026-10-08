> **Upgrading to v0.3:** Run `git pull --ff-only`, re-run the local development plugin from this checkout, and rebuild/update the `Mettle` Swift package. New exports use schema version 2; old runtimes refuse them. Older version-1 exports still load in the new runtime. See [Motion update](MOTION_2026_09.md).

# Run Mettle locally

**Recommended for the experimental build. No Figma Community publication is required.**

Mettle has three separate parts. The **Figma plugin** exports a design, the **Swift package** renders the export in your application, and **Mettle Preview** is an optional Mac utility for checking files. You do not need to ship the preview app with your product.

## 1. Get the repository

```bash
git clone https://github.com/Amal-David/mettle.git
cd mettle
```

Alternatively, choose **Code → Download ZIP** on GitHub and unzip it. Keep the folder in a stable location: Figma reads your plugin from that location.

## 2. Install the local Figma plugin

You need the **Figma desktop app**, not only a browser tab. Figma documents local plugin creation and import as available on any plan.

1. Open a Figma Design file in the desktop app.
2. Choose **Figma menu → Plugins → Development → Import new plugin from manifest…**.
3. Select `plugin/manifest.json` from this repository.
4. Run **Mettle — Experimental Metal Export** from Plugins → Development.

The repository includes `code.js` and `ui.html`. **You do not need Node, npm, Xcode, an API token, or a local server just to import and run the prebuilt exporter.** Node is only needed to change/rebuild/test its JavaScript source.

### If Figma asks for a plugin ID

The checked-in ID is for local development, not a published Community plugin. Use **Plugins → Development → New plugin → Figma design → Custom UI**, save the generated plugin, and copy the numeric `id` from its manifest. Then prepare an isolated local package:

```bash
python3 scripts/package_plugin.py --plugin-id YOUR_NUMERIC_ID
```

Import `artifacts/local-plugin/manifest.json`. This does not edit the tracked manifest and does not publish anything. Do not commit your local manifest back to the repository.

## 3. Export a design

Select **one frame or component**, run the plugin, and choose **Keyframe animation** or **Static artwork**. Review the compatibility report and leave incomplete diagnostic export unchecked. Save the `.figmetal.json` file. A selection with no captured tracks is explicitly labeled static.

For a bounded A/B transition, select two same-size source states and choose **Smart Animate · two states**. Follow the source interaction, or choose the start state explicitly for bidirectional connections. The captured connection supplies timing and easing; canvas position does not choose the direction. This does not export a general prototype state machine.

When the report flags artwork outside the nominal canvas, enable **Use Figma reference bounds** under the advanced options and inspect again. Static/two-state captures can use Figma's actual PNG dimensions and source render origin to preserve overflow. This requires unrotated source roots and matching local viewports for both states. Save the offered Figma PNGs separately; they are comparison references, not native renderer inputs.

**Save source capture** and **Save report** remain available when a scene is blocked. Clicking a diagnostic reveals its source layer. Reproduce a saved capture without Figma:

```bash
node scripts/compile_capture.mjs animation.source.json \
  --output animation.figmetal.json --report animation.report.json
```

The command writes the diagnostic scene and exits with failure if unsupported features remain. The normal preview rejects incomplete scenes. `--allow-partial` on the native CLI is an explicit debugging override, not a fidelity result. Read [compatibility](COMPATIBILITY.md) and the [real Community corpus](../fixtures/community/material3/README.md) before choosing source motion.

## 4. Preview on a Mac (optional)

A Metal-capable Mac and an installed Xcode/Swift toolchain are required. The package declares macOS 13+; actual verification environments are listed in [verification](VERIFICATION.md). For a quick environment check, use `xcode-select -p` and `swift --version`.

```bash
swift run -c release mettle preview
```

Use **Open animation…** (⌘O), or drag a `.figmetal.json` export into the window. Raw `.fig`, Lottie, SVG and `.riv` files are not supported inputs. The welcome screen does not automatically play test artwork.

The loaded-file controls are **Play/Pause**, **Restart**, the time slider, **Speed**, **Repeat**, **Zoom**, **Background**, and **Export frame…**. Space plays/pauses; arrow keys step by 1/30 second. After saving an updated source export, **Reload Export** (⇧⌘R) reloads it at the same playhead position. ⇧⌘E exports a PNG at the original canvas size. ⌘I reveals optional file/rendering details. Reduce Motion prevents playback. Appearance can be Light, Dark, or System.

```bash
# Open a specific exported file directly.
swift run -c release mettle preview /path/to/animation.figmetal.json

# Validate without opening the preview window.
swift run -c release mettle validate /path/to/animation.figmetal.json
```

**Motion references** is a credited inspiration gallery. Its Watch original links open the creators’ websites; those works are not native Mettle imports. The old test scenes are under **Developer → … (test fixture)**, not presented as design references. `mettle demo` remains an alias for `mettle preview`.

## 5. Use the library without the desktop app

Add this repository as a Swift Package in Xcode and link **Mettle**. Load your exported scene with `SceneDocument.load(url:)`, create a `MetalRenderer` once, and display it through `MettleView`. See the [README integration example](../README.md). The Figma exporter and Mac preview are not dependencies of your iOS runtime product.

## Update or modify

```bash
git pull --ff-only
# Only when modifying the exporter:
(cd plugin && npm run build && npm run check && npm test)
# Optional local plugin-only ZIP, using the current prebuilt JS:
python3 scripts/package_plugin.py
```

Restart the development plugin in Figma after updating. Re-run the Swift command to rebuild the preview. If the folder moved, re-import the manifest at its new location.

## Troubleshooting and privacy

- **Plugin missing:** use Figma Desktop, open a Design file, and check Plugins → Development. Re-import if the source folder moved.
- **Export is blocked:** read the report; simplify only the unsupported feature. Do not use incomplete export as a default workaround.
- **Cannot open a file:** choose the plugin’s `.figmetal.json`, not a raw design or external reference. An invalid file leaves the existing preview intact.
- **No Metal device / Xcode error:** run the native preview on a Metal-capable Mac with Xcode selected. The Figma plugin alone does not require Xcode.
- **Static frame:** a scene without tracks is labelled static, with playback disabled. Nothing is invented to make it move.
- **Cropped overflow:** use Figma reference bounds for static/two-state captures. Preserve the generated numeric viewport when replaying the source.
- **Frame output already exists:** choose a fresh directory. Native sequences refuse to mix an old manifest or frames with a new run.

The exporter requests no network access. Native preview/export reads local scene data. Reference links and the browser reference board visit external websites only when opened. Open only trusted exports; this experimental renderer is not a security sandbox.

## Official Figma instructions (checked 2026-09-30)

- [Create/import a plugin for development](https://help.figma.com/hc/en-us/articles/360042786733-Create-a-plugin-for-development)
- [Plugin quickstart](https://developers.figma.com/docs/plugins/plugin-quickstart-guide/)
- [Manifest and plugin IDs](https://developers.figma.com/docs/plugins/manifest/)
