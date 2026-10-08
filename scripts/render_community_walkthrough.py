#!/usr/bin/env python3
"""Render README media from the pinned Figma and native Metal evidence.

The presentation motion in this asset only moves labels and evidence cards. It
does not synthesize design interpolation or claim intermediate playback parity.
"""
from io import BytesIO
from pathlib import Path
from tempfile import TemporaryDirectory
import hashlib
import json
import subprocess
import zipfile

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
MEDIA = ROOT / "docs/media"
EVIDENCE = ROOT / "docs/verification"
WIDTH, HEIGHT, FPS, FRAMES = 1280, 720, 12, 120
BG, PANEL, LINE = "#0b1017", "#141c27", "#2a394b"
FG, MUTED, ACCENT, WARM = "#f4f7fb", "#9fb0c3", "#7ce6c4", "#f2c77e"
ARCHIVES = {
    "standard": ("community-standard-40008b5.zip", "29506abcca610f9843f91ab3c1dc50cd0af3357449226b1d78989d3ee31b0765"),
    "high": ("community-high-01fbeac.zip", "5984690d6eea78e7029778de4725fd593d01b015468d6a9d60653aaa9e464ee7"),
}


def font(size, bold=False):
    names = [
        Path("/usr/share/fonts/truetype/dejavu") / ("DejaVuSans-Bold.ttf" if bold else "DejaVuSans.ttf"),
        Path("/System/Library/Fonts/Supplemental") / ("Arial Bold.ttf" if bold else "Arial.ttf"),
    ]
    for name in names:
        if name.is_file():
            return ImageFont.truetype(str(name), size)
    return ImageFont.load_default(size=size)


def open_archive(profile):
    name, expected = ARCHIVES[profile]
    raw = (EVIDENCE / name).read_bytes()
    if hashlib.sha256(raw).hexdigest() != expected:
        raise ValueError(f"Pinned archive changed: {name}")
    archive = zipfile.ZipFile(BytesIO(raw))
    roots = [p.rsplit("/", 1)[0] for p in archive.namelist() if p.endswith("/report/comparison.json")]
    if len(roots) != 1:
        raise ValueError(f"Expected one comparison report in {name}")
    return archive, roots[0]


def read_png(archive, root, case, kind="reference", frame=0):
    path = f"{root}/{case}/{kind}-{frame:04d}.png"
    return Image.open(BytesIO(archive.read(path))).convert("RGBA")


def ease(value):
    value = max(0.0, min(1.0, value))
    return value * value * (3 - 2 * value)


def opacity(frame, start, end, fade=8):
    return ease(min((frame - start) / fade, (end - frame) / fade, 1.0))


def text(draw, xy, value, size, fill=FG, bold=False, anchor=None):
    draw.text(xy, value, font=font(size, bold), fill=fill, anchor=anchor)


def checker(size):
    tile = Image.new("RGB", size, "#1b2633")
    draw = ImageDraw.Draw(tile)
    for y in range(0, size[1], 12):
        for x in range(0, size[0], 12):
            if (x // 12 + y // 12) % 2:
                draw.rectangle((x, y, x + 11, y + 11), fill="#223043")
    return tile


def evidence_card(canvas, image, box, title, subtitle, border=LINE):
    x, y, w, h = box
    draw = ImageDraw.Draw(canvas)
    draw.rounded_rectangle((x, y, x + w, y + h), 20, fill=PANEL, outline=border, width=2)
    text(draw, (x + 20, y + 17), title, 20, FG, True)
    text(draw, (x + 20, y + 46), subtitle, 13, MUTED)
    art_box = (w - 40, h - 94)
    background = checker(art_box)
    factor = max(1, min((art_box[0] - 22) // image.width, (art_box[1] - 22) // image.height))
    scaled = image.resize((image.width * factor, image.height * factor), Image.Resampling.NEAREST)
    background.paste(scaled, ((art_box[0] - scaled.width) // 2, (art_box[1] - scaled.height) // 2), scaled)
    canvas.paste(background, (x + 20, y + 74))


def header(canvas, kicker, title_value, description, progress):
    draw = ImageDraw.Draw(canvas)
    text(draw, (58, 42), kicker.upper(), 14, ACCENT, True)
    text(draw, (58, 69), title_value, 42, FG, True)
    text(draw, (60, 124), description, 17, MUTED)
    draw.rounded_rectangle((58, 680, 1222, 686), 3, fill="#1e2a37")
    draw.rounded_rectangle((58, 680, 58 + int(1164 * progress), 686), 3, fill=ACCENT)
    text(draw, (1222, 667), "Mettle / Community verification", 12, MUTED, anchor="ra")


def compose(frame, high, high_root, standard, standard_root, summary):
    canvas = Image.new("RGB", (WIDTH, HEIGHT), BG)
    draw = ImageDraw.Draw(canvas)
    progress = frame / (FRAMES - 1)
    if frame < 24:
        alpha = opacity(frame, 0, 24, 7)
        header(canvas, "Figma source to Metal", "Real designs. Native evidence.",
               "Material 3 Community components, compiled and compared without tracing screenshots.", progress)
        stages = ["Figma", "Exporter", "Swift", "Metal", "Compare"]
        for index, stage in enumerate(stages):
            x = 65 + index * 238
            delay = 3 + index * 2
            lift = int(18 * (1 - ease((frame - delay) / 9)))
            color = ACCENT if index in (0, 3) else FG
            draw.rounded_rectangle((x, 278 + lift, x + 170, 374 + lift), 18, fill=PANEL, outline=LINE, width=2)
            text(draw, (x + 85, 326 + lift), stage, 21, color, True, anchor="mm")
            if index < 4:
                text(draw, (x + 198, 326), "→", 26, MUTED, True, anchor="mm")
        text(draw, (640, 482), "11 authentic source states  ·  19 replay cases", 24, FG, True, anchor="mm")
        text(draw, (640, 522), "Presentation motion only — no design interpolation is invented.", 15, WARM, anchor="mm")
        return canvas

    if frame < 50:
        header(canvas, "Captured source", "Four component families. Original pixels.",
               "Independent Figma exports remain immutable and hash-checked in the corpus.", progress)
        selected = [
            ("loading-step-1", "Loading", "7 creator states"),
            ("switch-hovered", "Switch", "Enabled + hovered"),
            ("circular-wave-step-1", "Circular", "Fractional viewport"),
            ("linear-flat-step-1", "Linear", "404 × 12 source"),
        ]
        for index, (case, title_value, subtitle) in enumerate(selected):
            image = read_png(high, high_root, case)
            evidence_card(canvas, image, (55 + index * 302, 190, 270, 365), title_value, subtitle)
        text(draw, (640, 608), "Source identities, reactions, bounds, timing and SHA-256 fingerprints travel together.",
             16, MUTED, anchor="mm")
        return canvas

    if frame < 75:
        header(canvas, "Supported motion", "The genuine 200 ms hover survives export.",
               "Two source endpoints become native paint bindings with captured timing and easing.", progress)
        start = read_png(high, high_root, "switch-hover", "reference", 0)
        end = read_png(high, high_root, "switch-hover", "reference", 1)
        evidence_card(canvas, start, (125, 195, 390, 350), "Enabled", "Figma reference · t = 0.0 s", ACCENT)
        evidence_card(canvas, end, (765, 195, 390, 350), "Hovered", "Figma reference · t = 0.20000000298 s", ACCENT)
        text(draw, (640, 355), "→", 52, ACCENT, True, anchor="mm")
        text(draw, (640, 414), "2 color bindings", 17, FG, True, anchor="mm")
        text(draw, (640, 444), "0 diagnostics", 14, MUTED, anchor="mm")
        text(draw, (640, 608), "Endpoint parity verified. Intermediate prototype playback remains explicitly unverified.",
             15, WARM, anchor="mm")
        return canvas

    if frame < 100:
        header(canvas, "Renderer repair", "High quality fixes edge coverage.",
               "The source geometry, camera, timestamps and acceptance gates did not change.", progress)
        reference = read_png(high, high_root, "circular-wave-step-1", "reference")
        before = read_png(standard, standard_root, "circular-wave-step-1", "native")
        after = read_png(high, high_root, "circular-wave-step-1", "native")
        evidence_card(canvas, reference, (55, 190, 350, 350), "Figma reference", "Original 49 × 49 PNG")
        evidence_card(canvas, before, (465, 190, 350, 350), "Standard", "Foreground RGB error 7.242 / 255")
        evidence_card(canvas, after, (875, 190, 350, 350), "High quality", "Foreground RGB error 0.343 / 255", ACCENT)
        text(draw, (640, 607), "2× internal raster + premultiplied Metal resolve  ·  all foreground bounds exact",
             16, ACCENT, True, anchor="mm")
        return canvas

    header(canvas, "Verified result", "12 / 12 native cases pass.",
           "Thirteen exact endpoint frames passed the original pixel gates on Metal.", progress)
    stats = [("108", "Swift tests"), ("105", "JS tests"), ("28", "Python tests"), ("7", "expected blockers")]
    for index, (value, label) in enumerate(stats):
        x = 75 + index * 300
        draw.rounded_rectangle((x, 205, x + 250, 370), 22, fill=PANEL, outline=ACCENT if index < 3 else WARM, width=2)
        text(draw, (x + 125, 260), value, 50, FG, True, anchor="mm")
        text(draw, (x + 125, 326), label, 16, MUTED, anchor="mm")
    draw.rounded_rectangle((110, 432, 1170, 576), 22, fill="#101923", outline=LINE, width=2)
    text(draw, (145, 466), "Verified", 14, ACCENT, True)
    text(draw, (145, 496), "Static source states + both Switch hover endpoints", 22, FG, True)
    text(draw, (145, 535), "Still explicit", 14, WARM, True)
    text(draw, (270, 535), "Loader path morphs and intermediate playback are not claimed.", 15, MUTED)
    return canvas


def main():
    high, high_root = open_archive("high")
    standard, standard_root = open_archive("standard")
    summary = json.loads((EVIDENCE / "community-results.json").read_text())
    if summary["highPassedCases"] != 12 or summary["motionPlaybackVerified"] is not False:
        raise ValueError("Unexpected Community evidence summary")
    MEDIA.mkdir(parents=True, exist_ok=True)
    overview = compose(108, high, high_root, standard, standard_root, summary)
    overview.save(MEDIA / "community-overview.png", optimize=True)
    with TemporaryDirectory(prefix="mettle-community-walkthrough-") as temporary:
        frames = Path(temporary)
        for index in range(FRAMES):
            compose(index, high, high_root, standard, standard_root, summary).save(frames / f"{index:04d}.png")
        subprocess.run(["ffmpeg", "-y", "-v", "error", "-framerate", str(FPS), "-i", str(frames / "%04d.png"),
            "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "20", "-movflags", "+faststart",
            str(MEDIA / "community-walkthrough.mp4")], check=True)
        subprocess.run(["ffmpeg", "-y", "-v", "error", "-framerate", str(FPS), "-i", str(frames / "%04d.png"),
            "-filter_complex", "fps=12,scale=960:-1:flags=lanczos,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=sierra2_4a",
            "-loop", "0", str(MEDIA / "community-walkthrough.gif")], check=True)
    print("Wrote docs/media/community-overview.png and community-walkthrough.{gif,mp4}")


if __name__ == "__main__":
    main()
