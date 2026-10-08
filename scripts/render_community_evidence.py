#!/usr/bin/env python3
"""Build a review figure and summary from the two unchanged native CI archives.

This composes measured evidence for display. It never renders a scene, changes
reference PNGs, or supplies reference pixels to Metal.
"""
from io import BytesIO
from pathlib import Path
import hashlib
import json
import zipfile

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
EVIDENCE = ROOT / "docs/verification"
PROFILES = {
    "standard": {"file": "community-standard-40008b5.zip", "rasterScale": 1,
        "sha256": "29506abcca610f9843f91ab3c1dc50cd0af3357449226b1d78989d3ee31b0765",
        "commit": "40008b52624968392690a1e82092db573fc979fb", "run": 37771004412},
    "high": {"file": "community-high-01fbeac.zip", "rasterScale": 2,
        "sha256": "5984690d6eea78e7029778de4725fd593d01b015468d6a9d60653aaa9e464ee7",
        "commit": "01fbeacd4692a6182711f0f1781cbfabc7452008", "run": 37772525330},
}


def read_profile(name):
    metadata = PROFILES[name]
    raw = (EVIDENCE / metadata["file"]).read_bytes()
    assert hashlib.sha256(raw).hexdigest() == metadata["sha256"], "CI archive changed"
    archive = zipfile.ZipFile(BytesIO(raw))
    reports = [p for p in archive.namelist() if p.endswith("/report/comparison.json")]
    assert len(reports) == 1
    report = json.loads(archive.read(reports[0]))
    return archive, reports[0].rsplit("/", 1)[0], report


def font(size, bold=False):
    candidates = [
        Path("/usr/share/fonts/truetype/dejavu") / ("DejaVuSans-Bold.ttf" if bold else "DejaVuSans.ttf"),
        Path("/System/Library/Fonts/Supplemental") / ("Arial Bold.ttf" if bold else "Arial.ttf"),
    ]
    for candidate in candidates:
        if candidate.is_file():
            return ImageFont.truetype(str(candidate), size)
    return ImageFont.load_default(size=size)


def main():
    standard, standard_root, before = read_profile("standard")
    high, high_root, after = read_profile("high")
    assert before["corpusSHA256"] == after["corpusSHA256"]
    assert before["thresholds"] == after["thresholds"], "Pixel gates changed"
    assert after["pass"] and after["comparedCases"] == 12
    old_cases = {c["id"]: c for c in before["cases"]}
    cases = {c["id"]: c for c in after["cases"]}
    comparisons = []
    for case_id, case in cases.items():
        previous = old_cases[case_id]
        assert case["sourceSHA256"] == previous["sourceSHA256"]
        for old, current in zip(previous["frames"], case["frames"]):
            assert old["referenceSHA256"] == current["referenceSHA256"] and old["time"] == current["time"]
            comparisons.append({"case": case_id, "time": current["time"],
                "referenceSHA256": current["referenceSHA256"],
                "standard": {"foregroundRGBMAE": old["foreground"]["rgbMAE"],
                    "foregroundAlphaMAE": old["foreground"]["alphaMAE"],
                    "wholePixelsOver8Percent": old["whole"]["pixelsOver8Percent"], "boundsError": old["boundsError"]},
                "high": {"foregroundRGBMAE": current["foreground"]["rgbMAE"],
                    "foregroundAlphaMAE": current["foreground"]["alphaMAE"],
                    "wholePixelsOver8Percent": current["whole"]["pixelsOver8Percent"], "boundsError": current["boundsError"]}})
    summary = {"format": "mettle-community-before-after", "version": 1,
        "profiles": PROFILES, "corpusSHA256": after["corpusSHA256"],
        "standardPassedCases": sum(c["pixelPass"] is True for c in before["cases"]),
        "highPassedCases": sum(c["pixelPass"] is True for c in after["cases"]),
        "renderCases": 12, "measuredFrames": len(comparisons), "expectedBlockedCases": 7,
        "motionPlaybackVerified": False, "sourceAndGatesUnchanged": True,
        "device": cases["switch-hover"]["device"], "measurements": comparisons}
    (EVIDENCE / "community-results.json").write_text(json.dumps(summary, indent=2) + "\n")

    image = Image.new("RGB", (1320, 1130), "#10151d")
    draw = ImageDraw.Draw(image)
    draw.text((38, 27), "Figma Community → native Metal", font=font(35, True), fill="#edf1f8")
    draw.text((40, 78), "13 source endpoint frames · 12/12 render cases pass at High quality", font=font(19), fill="#b8cadf")
    titles = [("Figma reference", "Original source PNG"), ("Standard", "4× MSAA"),
              ("High quality", "2× raster + 4× MSAA"), ("High difference", "Channel error amplified 4×")]
    columns = [40, 362, 684, 1006]
    for x, (title, subtitle) in zip(columns, titles):
        draw.text((x, 130), title, font=font(21, True), fill="#edf1f8")
        draw.text((x, 160), subtitle, font=font(15), fill="#98afc9")
    selected = [("circular-wave-step-1", "Circular wave"), ("switch-hovered", "Switch · hovered"),
                ("loading-step-1", "Expressive loading · state 1")]
    for row, (case_id, title) in enumerate(selected):
        top = 203 + row * 275
        draw.text((40, top), title, font=font(18, True), fill="#d5dfed")
        paths = [(high, high_root, "reference"), (standard, standard_root, "native"),
                 (high, high_root, "native"), (high, high_root, "difference")]
        for col, (archive, root, kind) in enumerate(paths):
            tile = Image.new("RGB", (272, 207), "#202b3a")
            checker = ImageDraw.Draw(tile)
            for y in range(0, 207, 12):
                for x in range(0, 272, 12):
                    if (x//12 + y//12) % 2:
                        checker.rectangle((x, y, x+11, y+11), fill="#293649")
            source = Image.open(BytesIO(archive.read(f"{root}/{case_id}/{kind}-0000.png"))).convert("RGBA")
            factor = max(1, min(248//source.width, 193//source.height))
            enlarged = source.resize((source.width*factor, source.height*factor), Image.Resampling.NEAREST)
            tile.paste(enlarged, ((272-enlarged.width)//2, (207-enlarged.height)//2), enlarged)
            image.paste(tile, (columns[col], top+30))
            if col in (1, 2):
                measurement = (old_cases if col == 1 else cases)[case_id]["frames"][0]
                label = f"Foreground RGB error: {measurement['foreground']['rgbMAE']:.3f} / 255"
            else:
                label = "Magnified view; original pixels retained" if col == 0 else "Derived diagnostic image"
            draw.text((columns[col], top+243), label, font=font(12), fill="#b8cadf")
    draw.line((40, 1040, 1278, 1040), fill="#394454", width=1)
    draw.text((40, 1054), "Source: Material 3 Design Kit, Google / Material Design · CC BY 4.0", font=font(15), fill="#b8cadf")
    draw.text((40, 1080), "Metal: Apple Paravirtual device. Original source and gates held fixed. Intermediate playback remains unverified.",
              font=font(14), fill="#98afc9")
    destination = ROOT / "docs/media/community-fidelity.png"
    image.save(destination, optimize=True)
    print(f"Wrote {destination.relative_to(ROOT)} and docs/verification/community-results.json")


if __name__ == "__main__":
    main()
