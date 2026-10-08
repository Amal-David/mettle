#!/usr/bin/env python3
"""Compare hash-locked Figma references with separately generated Metal frames.

This is an evidence gate, not a golden-image generator. Source PNGs are never
cropped, resized, recolored, or replaced. Endpoint-state checks do not certify
intermediate prototype playback. Uses the existing premultiplied RGBA metric.
"""
from __future__ import annotations

import argparse
import hashlib
import html
import json
import math
from pathlib import Path
import re
import shutil
import subprocess
import sys
from urllib.parse import urlparse

from PIL import Image, ImageChops
from compare_live import metrics

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_CORPUS = ROOT / "fixtures/community/material3/corpus.json"
TIME_TOLERANCE = 1e-9
ID = re.compile(r"[a-z0-9][a-z0-9_-]{0,79}\Z")
SHA256 = re.compile(r"[0-9a-f]{64}\Z")
METRICS = {"rgbMAE", "alphaMAE", "p95MaxChannelError", "p99MaxChannelError", "pixelsOver8Percent", "maxError"}


class EvidenceError(ValueError):
    """Missing, stale, ambiguous, or incompatible comparison evidence."""


def require(condition, message):
    if not condition:
        raise EvidenceError(message)


def number(value, label, minimum=0, maximum=86400):
    require(isinstance(value, (int, float)) and not isinstance(value, bool)
            and math.isfinite(value) and minimum <= value <= maximum, f"{label}: invalid number")
    return value


def integer(value, label, minimum=0, maximum=8192):
    require(isinstance(value, int) and not isinstance(value, bool) and minimum <= value <= maximum,
            f"{label}: invalid integer")
    return value


def same_time(a, b):
    return math.isclose(a, b, rel_tol=0, abs_tol=TIME_TOLERANCE)


def load_json(path):
    def unique(pairs):
        result = {}
        for key, value in pairs:
            require(key not in result, f"{path}: duplicate JSON key {key}")
            result[key] = value
        return result

    def invalid_constant(value):
        raise EvidenceError(f"{path}: nonfinite JSON number {value}")

    try:
        return json.loads(path.read_text(), object_pairs_hook=unique, parse_constant=invalid_constant)
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise EvidenceError(f"Cannot read JSON {path}: {error}") from error


def digest(path):
    try:
        with path.open("rb") as source:
            value = hashlib.sha256()
            for block in iter(lambda: source.read(1024 * 1024), b""):
                value.update(block)
            return value.hexdigest()
    except OSError as error:
        raise EvidenceError(f"Cannot read artifact {path}: {error}") from error


def child_path(root, relative, label):
    require(isinstance(relative, str) and relative and "\\" not in relative,
            f"{label}: invalid relative path")
    value = Path(relative)
    require(not value.is_absolute() and ".." not in value.parts, f"{label}: path escapes evidence directory")
    result = (root / value).resolve()
    require(result.is_relative_to(root.resolve()), f"{label}: symlink escapes evidence directory")
    return result


def artifact(root, entry, label):
    require(isinstance(entry, dict), f"{label}: missing artifact descriptor")
    require(isinstance(entry.get("sha256"), str) and SHA256.fullmatch(entry["sha256"]), f"{label}: missing SHA256")
    path = child_path(root, entry.get("path"), label)
    require(path.is_file(), f"{label}: missing {path}")
    require(digest(path) == entry["sha256"], f"{label}: SHA256 mismatch for {path.name}")
    return path


def png(path, expected_size=None):
    try:
        with Image.open(path) as source:
            require(source.format == "PNG", f"{path}: expected original PNG")
            require(source.width > 0 and source.height > 0 and source.width * source.height <= 8_388_608,
                    f"{path}: PNG exceeds comparison size limit")
            if expected_size:
                require(source.size == expected_size, f"{path}: dimensions {source.size} != {expected_size}")
            source.load()
            return source.convert("RGBA")
    except (OSError, Image.DecompressionBombError) as error:
        raise EvidenceError(f"Cannot read PNG {path}: {error}") from error


def validate_viewport(value, label):
    require(isinstance(value, dict), f"{label}: missing viewport")
    number(value.get("x"), f"{label}.x", -1e9, 1e9)
    number(value.get("y"), f"{label}.y", -1e9, 1e9)
    width = integer(value.get("width"), f"{label}.width", 1)
    height = integer(value.get("height"), f"{label}.height", 1)
    require(width * height <= 8_388_608, f"{label}: viewport exceeds 8 megapixels")
    return width, height


def validate_thresholds(value):
    require(isinstance(value, dict), "Missing measurement thresholds")
    for section in ("whole", "foreground", "regions"):
        limits = value.get(section)
        require(isinstance(limits, dict) and {"rgbMAE", "alphaMAE"} <= set(limits), f"Missing {section} RGB/alpha gates")
        require(set(limits) <= METRICS, f"Unknown {section} metric gate")
        for name, maximum in limits.items():
            number(maximum, f"{section}.{name}", 0, 100 if name == "pixelsOver8Percent" else 255)
    number(value.get("boundsMaxPixels"), "boundsMaxPixels", 0, 8192)


def prepare(corpus_path):
    """Validate source provenance and compile artifacts without claiming pixels."""
    corpus_path = corpus_path.resolve()
    root = corpus_path.parent
    corpus = load_json(corpus_path)
    require(corpus.get("format") == "mettle-comparison-corpus" and corpus.get("version") == 1,
            "Expected mettle-comparison-corpus version 1")
    validate_thresholds(corpus.get("thresholds"))
    provenance = load_json(artifact(root, corpus.get("provenance"), "provenance"))
    require(provenance.get("format") == "mettle-community-provenance" and provenance.get("version") == 1,
            "Expected Community source provenance version 1")
    url = urlparse(provenance.get("communityURL", ""))
    require(url.scheme == "https" and url.hostname in {"figma.com", "www.figma.com"} and url.path.startswith("/community/file/"),
            "Provenance must identify the original Figma Community resource")
    require(provenance.get("captureFileKey") and provenance.get("capturedDate"), "Missing source capture identity/date")
    for entry in corpus.get("sourceEvidence", []):
        artifact(root, entry, "source evidence")
    if "sourceBounds" in provenance:
        artifact(root, provenance["sourceBounds"], "source bounds")

    fixtures = {}
    require(isinstance(provenance.get("fixtures"), list) and provenance["fixtures"], "Missing source fixtures")
    for fixture in provenance["fixtures"]:
        slug = fixture.get("slug")
        require(isinstance(slug, str) and ID.fullmatch(slug) and slug not in fixtures, "Invalid/duplicate source fixture ID")
        snapshot_path = artifact(root, fixture.get("snapshot"), f"{slug} snapshot")
        snapshot = load_json(snapshot_path)
        require(snapshot.get("id") == fixture.get("instanceId") and fixture.get("sourceFrameId"), f"{slug}: source node identity mismatch")
        if "sourceComponent" in fixture:
            require(snapshot.get("sourceComponent") == fixture["sourceComponent"], f"{slug}: source component identity mismatch")
        references = fixture.get("references", [fixture.get("reference")])
        require(isinstance(references, list) and references, f"{slug}: missing independent references")
        reference_map = {}
        for reference in references:
            path = artifact(root, reference, f"{slug} reference")
            require(reference.get("method") in {"figma.exportAsync/png", "figma.timeline/png"}, f"{slug}: reference is not an independent Figma export")
            require(reference.get("sourceFrameId") == fixture["sourceFrameId"], f"{slug}: reference source frame identity mismatch")
            size = validate_viewport(reference.get("viewport"), f"{slug} reference viewport")
            require((reference.get("width"), reference.get("height")) == size, f"{slug}: reference dimensions disagree with viewport")
            require(reference["path"] not in reference_map, f"{slug}: duplicate reference path")
            png(path, size)
            reference_map[reference["path"]] = {**reference, "resolvedPath": path}
        fixtures[slug] = {**fixture, "snapshotData": snapshot, "referenceMap": reference_map}

    cases = corpus.get("cases")
    require(isinstance(cases, list) and cases, "Corpus has no cases")
    prepared = []
    seen = set()
    for case in cases:
        case_id = case.get("id")
        require(isinstance(case_id, str) and ID.fullmatch(case_id) and case_id not in seen, "Invalid/duplicate case ID")
        seen.add(case_id)
        require(case.get("expectation") in {"render", "blocked"}, f"{case_id}: invalid expectation")
        require(case.get("coverage") in {"static", "endpoint-states", "timeline-frames"}, f"{case_id}: invalid coverage")
        slugs = case.get("sourceFixtures")
        require(isinstance(slugs, list) and slugs and len(slugs) == len(set(slugs)) and all(x in fixtures for x in slugs),
                f"{case_id}: missing/duplicate source fixture binding")
        source_path = artifact(root, case.get("source"), f"{case_id} source bundle")
        source = load_json(source_path)
        require(source.get("format") == "mettle-source" and source.get("version") == 1, f"{case_id}: invalid replay source bundle")
        require(source.get("nodes") == [fixtures[x]["snapshotData"] for x in slugs], f"{case_id}: source bundle differs from captured snapshots")
        require(source.get("provenance", {}).get("sourceManifest", {}).get("sha256") == corpus["provenance"]["sha256"],
                f"{case_id}: source bundle provenance mismatch")
        document_path = artifact(root, case.get("document"), f"{case_id} compiled document")
        document = load_json(document_path)
        require(document.get("format") == "figma-metal" and document.get("version") in {1, 2}, f"{case_id}: wrong compiled format")
        require(document.get("provenance", {}).get("sourceCaptureSHA256") == case["source"]["sha256"],
                f"{case_id}: compiled source capture SHA256 mismatch")
        scenes = document.get("scenes")
        index = integer(case.get("sceneIndex"), f"{case_id}.sceneIndex", 0, 63)
        require(isinstance(scenes, list) and index < len(scenes), f"{case_id}: scene index out of range")
        scene = scenes[index]
        size = validate_viewport(case.get("viewport"), f"{case_id} viewport")
        require((scene.get("width"), scene.get("height")) == size, f"{case_id}: compiled scene dimensions mismatch")
        require(source.get("options", {}).get("viewport") == case["viewport"], f"{case_id}: source viewport mismatch")
        duration = number(case.get("duration"), f"{case_id}.duration")
        require(same_time(number(scene.get("duration"), f"{case_id} scene duration"), duration), f"{case_id}: compiled duration mismatch")
        require(case.get("loop") == "once", f"{case_id}: comparisons must use once to retain the endpoint")
        diagnostics = document.get("diagnostics")
        require(isinstance(diagnostics, list), f"{case_id}: missing compiler diagnostics")
        codes = {d.get("code") for d in diagnostics if d.get("severity") == "error"}
        if case["expectation"] == "blocked":
            expected = case.get("expectedErrorCodes")
            require(isinstance(expected, list) and expected and len(expected) == len(set(expected)), f"{case_id}: missing blocker contract")
            require(codes == set(expected), f"{case_id}: blocker diagnostics changed: {sorted(codes)}")
        else:
            require(not codes, f"{case_id}: compiled document contains blocking errors: {sorted(codes)}")
        frames = case.get("referenceFrames")
        require(isinstance(frames, list) and frames, f"{case_id}: missing reference schedule")
        resolved = []
        previous = -1
        for i, frame in enumerate(frames):
            require(integer(frame.get("index"), f"{case_id} reference index", 0, 3599) == i, f"{case_id}: reference indices are not contiguous")
            time = number(frame.get("time"), f"{case_id} reference time")
            require(time > previous and time <= duration + TIME_TOLERANCE, f"{case_id}: reference times are out of order/range")
            previous = time
            slug = frame.get("fixture")
            require(slug in slugs, f"{case_id}: reference is unrelated to source fixtures")
            fixture = fixtures[slug]
            relative = frame.get("referencePath", fixture.get("reference", {}).get("path"))
            require(relative in fixture["referenceMap"], f"{case_id}: reference is not pinned by source provenance")
            reference = fixture["referenceMap"][relative]
            require(reference["viewport"] == case["viewport"], f"{case_id}: source/reference camera mismatch")
            if case["coverage"] == "timeline-frames":
                require(reference["method"] == "figma.timeline/png" and same_time(number(reference.get("time"), "captured timeline time"), time),
                        f"{case_id}: endpoint-state exports cannot be relabeled as timeline samples")
            resolved.append({**frame, "reference": reference})
        require(same_time(frames[0]["time"], 0) and same_time(frames[-1]["time"], duration), f"{case_id}: start or final endpoint is missing")
        if case["coverage"] == "static":
            require(duration == 0 and len(frames) == 1 and source.get("mode") == "static", f"{case_id}: static coverage has a timeline")
        else:
            require(duration > 0 and len(frames) >= (3 if case["coverage"] == "timeline-frames" else 2), f"{case_id}: incomplete motion reference schedule")
        foreground = case.get("foreground")
        require(isinstance(foreground, dict) and isinstance(foreground.get("backgroundRGBA"), list) and len(foreground["backgroundRGBA"]) == 4,
                f"{case_id}: foreground needs an explicit source background RGBA")
        for value in foreground["backgroundRGBA"]:
            integer(value, "background channel", 0, 255)
        integer(foreground.get("threshold"), "foreground threshold", 0, 255)
        regions = case.get("regions")
        require(isinstance(regions, list) and regions, f"{case_id}: at least one regional gate is required")
        region_ids = set()
        for region in regions:
            region_id = region.get("id")
            require(isinstance(region_id, str) and ID.fullmatch(region_id) and region_id not in region_ids, f"{case_id}: invalid/duplicate region ID")
            region_ids.add(region_id)
            box = region.get("rect")
            require(isinstance(box, list) and len(box) == 4 and all(isinstance(x, int) and not isinstance(x, bool) for x in box), f"{case_id}: invalid region")
            require(0 <= box[0] < box[2] <= size[0] and 0 <= box[1] < box[3] <= size[1], f"{case_id}: region exceeds image bounds")
        prepared.append({**case, "documentPath": document_path, "resolvedFrames": resolved, "diagnostics": diagnostics})
    return {"corpusPath": corpus_path, "root": root, "data": corpus, "provenance": provenance, "cases": prepared}


def foreground_mask(image, background, threshold):
    premultiplied = image.convert("RGBA").convert("RGBa")
    background_image = Image.new("RGBA", image.size, tuple(background)).convert("RGBa")
    channels = ImageChops.difference(premultiplied, background_image).split()
    maximum = channels[0]
    for channel in channels[1:]:
        maximum = ImageChops.lighter(maximum, channel)
    return maximum.point(lambda value: 255 if value > threshold else 0)


def measure(reference, actual, case):
    require(reference.size == actual.size, "Native/reference dimensions differ")
    foreground = case["foreground"]
    rmask = foreground_mask(reference, foreground["backgroundRGBA"], foreground["threshold"])
    amask = foreground_mask(actual, foreground["backgroundRGBA"], foreground["threshold"])
    union = ImageChops.lighter(rmask, amask)
    indices = [i for i, value in enumerate(union.tobytes()) if value]
    if indices:
        selected = []
        for image in (reference, actual):
            data = image.convert("RGBA").tobytes()
            selected.append(Image.frombytes("RGBA", (len(indices), 1), b"".join(data[i*4:i*4+4] for i in indices)))
        fg = metrics(*selected)
    else:
        empty = Image.new("RGBA", (1, 1))
        fg = metrics(empty, empty)
    rb, ab = rmask.getbbox(), amask.getbbox()
    bounds_error = max(abs(a-b) for a, b in zip(rb, ab)) if rb and ab else (0 if rb == ab else max(reference.size))
    return {"whole": metrics(reference, actual), "foreground": {**fg, "pixelCount": len(indices)},
            "referenceBounds": rb, "nativeBounds": ab, "boundsError": bounds_error,
            "regions": {r["id"]: metrics(reference.crop(r["rect"]), actual.crop(r["rect"])) for r in case["regions"]}}


def gate_measurements(measurement, thresholds):
    gates = []
    groups = [("whole", measurement["whole"], thresholds["whole"]),
              ("foreground", measurement["foreground"], thresholds["foreground"])]
    groups += [(f"region/{name}", values, thresholds["regions"]) for name, values in measurement["regions"].items()]
    for group, values, limits in groups:
        for name, maximum in limits.items():
            gates.append({"name": f"{group}/{name}", "actual": values[name], "maximum": maximum, "pass": values[name] <= maximum})
    gates.append({"name": "foreground/boundsMaxPixels", "actual": measurement["boundsError"],
                  "maximum": thresholds["boundsMaxPixels"], "pass": measurement["boundsError"] <= thresholds["boundsMaxPixels"]})
    return gates


def native_frames(case, directory, expected_raster_scale=None):
    require(directory.is_dir(), f"{case['id']}: missing native evidence directory")
    manifest_path = directory / "manifest.json"
    manifest = load_json(manifest_path)
    require(manifest.get("format") == "mettle-frames" and manifest.get("version") == 1 and manifest.get("backend") == "Metal",
            f"{case['id']}: expected a native Metal frame manifest")
    require(manifest.get("sourceSHA256") == case["document"]["sha256"], f"{case['id']}: native source SHA256 mismatch")
    require(integer(manifest.get("sceneIndex"), "native sceneIndex", 0, 63) == case["sceneIndex"], f"{case['id']}: native scene index mismatch")
    require(same_time(number(manifest.get("sceneDuration"), "native sceneDuration"), case["duration"]), f"{case['id']}: native timeline duration mismatch")
    require(manifest.get("loop") == case["loop"], f"{case['id']}: native loop would wrap the endpoint")
    size = case["viewport"]["width"], case["viewport"]["height"]
    require((integer(manifest.get("width"), "native width", 1), integer(manifest.get("height"), "native height", 1)) == size,
            f"{case['id']}: native manifest dimensions mismatch")
    require(isinstance(manifest.get("device"), str) and manifest["device"].strip(), f"{case['id']}: missing native device identity")
    number(manifest.get("curveTolerance"), "native curveTolerance", minimum=1e-9, maximum=1)
    require(integer(manifest.get("sampleCount"), "native sampleCount", 1, 32) in (1, 2, 4, 8, 16, 32),
            f"{case['id']}: invalid native MSAA sample count")
    raster_scale = integer(manifest.get("rasterScale", 1), "native rasterScale", 1, 2)
    if expected_raster_scale is not None:
        require(raster_scale == expected_raster_scale, f"{case['id']}: native raster scale differs from the requested quality")
    for key, dimension in zip(("rasterWidth", "rasterHeight"), size):
        if key in manifest:
            require(integer(manifest[key], f"native {key}", 1) == dimension * raster_scale,
                    f"{case['id']}: inconsistent internal raster dimensions")
    frames = manifest.get("frames")
    require(isinstance(frames, list) and len(frames) == len(case["resolvedFrames"]), f"{case['id']}: native frame count mismatch")
    names, output = set(), []
    for i, (entry, reference) in enumerate(zip(frames, case["resolvedFrames"])):
        require(integer(entry.get("index"), "native frame index", 0, 3599) == i, f"{case['id']}: native frame indices are not contiguous")
        require(same_time(number(entry.get("time"), "native frame time"), reference["time"]), f"{case['id']}: native timestamp mismatch at frame {i}")
        name = entry.get("file")
        require(isinstance(name, str) and Path(name).name == name and name.endswith(".png") and name not in names,
                f"{case['id']}: duplicate/invalid native PNG filename")
        names.add(name)
        path = artifact(directory, {"path": name, "sha256": entry.get("sha256")}, f"{case['id']} frame {i}")
        png(path, size)
        output.append({"path": path, "sha256": entry["sha256"]})
    require({p.name for p in directory.glob("*.png")} == names, f"{case['id']}: stale/unlisted native PNG frames")
    return manifest, output


def compare(prepared, native_root, expected_raster_scale=None):
    results = []
    for case in prepared["cases"]:
        result = {"id": case["id"], "expectation": case["expectation"], "coverage": case["coverage"],
                  "sourceSHA256": case["document"]["sha256"], "frames": [], "pixelPass": None,
                  "motionPlaybackVerified": False}
        directory = native_root / case["id"]
        try:
            if case["expectation"] == "blocked":
                require(not (directory / "manifest.json").exists() and not list(directory.glob("*.png")),
                        f"{case['id']}: blocked conversion has unexpected native output")
                result.update(status="blocked-as-expected", passContract=True, expectedErrorCodes=case["expectedErrorCodes"], diagnostics=case["diagnostics"])
            else:
                manifest, frames = native_frames(case, directory, expected_raster_scale)
                result["nativeManifestSHA256"] = digest(directory / "manifest.json")
                result["device"] = manifest["device"]
                result["renderSettings"] = {"curveTolerance": manifest["curveTolerance"],
                    "sampleCount": manifest["sampleCount"], "rasterScale": manifest.get("rasterScale", 1)}
                for reference, actual in zip(case["resolvedFrames"], frames):
                    measurement = measure(png(reference["reference"]["resolvedPath"]), png(actual["path"]), case)
                    gates = gate_measurements(measurement, prepared["data"]["thresholds"])
                    result["frames"].append({"index": reference["index"], "time": reference["time"],
                                             "referenceSHA256": reference["reference"]["sha256"], "nativeSHA256": actual["sha256"],
                                             **measurement, "gates": gates, "pass": all(g["pass"] for g in gates)})
                result["pixelPass"] = all(frame["pass"] for frame in result["frames"])
                result.update(status="pixels-passed" if result["pixelPass"] else "pixels-failed", passContract=result["pixelPass"])
                result["motionPlaybackVerified"] = result["pixelPass"] and case["coverage"] == "timeline-frames"
        except (EvidenceError, OSError) as error:
            result.update(status="evidence-failed", passContract=False, error=str(error))
        results.append(result)
    renders = [x for x in results if x["expectation"] == "render"]
    return {"format": "mettle-corpus-comparison", "version": 1, "corpusSHA256": digest(prepared["corpusPath"]),
            "sourceIntegrityPass": True, "pass": all(x["passContract"] for x in results),
            "pixelPass": all(x["pixelPass"] is True for x in renders) if renders else None,
            "renderCases": len(renders), "comparedCases": sum(x["pixelPass"] is not None for x in renders),
            "expectedBlockedCases": sum(x["status"] == "blocked-as-expected" for x in results),
            "motionPlaybackVerified": any(x["motionPlaybackVerified"] for x in results),
            "limitations": ["Endpoint-state PNG equality does not establish intermediate Smart Animate playback fidelity.",
                            "Only the declared source frames, dimensions, times and regions are measured.",
                            "Thresholds are engineering regression gates, not pixel-perfect certification."],
            "thresholds": prepared["data"]["thresholds"], "cases": results}


STYLE = """body{font:16px system-ui;background:#10151d;color:#edf1f8;max-width:1300px;margin:40px auto;padding:0 24px}p{line-height:1.55}.grid{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:16px}figure{margin:0}img{width:100%;max-width:480px;image-rendering:auto;background:repeating-conic-gradient(#2b3546 0% 25%,#1c2532 0% 50%) 50%/16px 16px}figcaption{padding:8px 0}table{border-collapse:collapse;width:100%;margin:20px 0}td,th{border-bottom:1px solid #394454;text-align:left;padding:8px}a{color:#9dc7ff}.bad{color:#ffb4ab}.good{color:#a5e0b3}code{overflow-wrap:anywhere}section{margin:36px 0}small{color:#aebcd0}@media(max-width:650px){.grid{grid-template-columns:1fr}}"""


def write_report(prepared, summary, native_root, output):
    output = output.resolve()
    for evidence_root in (prepared["root"], native_root.resolve()):
        require(not output.is_relative_to(evidence_root) and not evidence_root.is_relative_to(output),
                "Report directory must be separate from source fixtures and native evidence")
    output.mkdir(parents=True, exist_ok=True)
    provenance = prepared["provenance"]
    source_url = html.escape(provenance["communityURL"], quote=True)
    creator = html.escape(provenance.get("creator", {}).get("name", "Creator identified in source provenance"))
    license_info = provenance.get("license", {})
    license_url = license_info.get("url", "")
    license_link = (f' · <a href="{html.escape(license_url, quote=True)}">{html.escape(license_info.get("spdx", "Source license"))}</a>'
                    if urlparse(license_url).scheme == "https" else "")
    attribution = f'<p><small>Source artwork: <a href="{source_url}">{creator}</a>{license_link}. Native conversion and comparison by Mettle. Original Figma PNGs are unchanged.</small></p>'
    links = []
    for case, result in zip(prepared["cases"], summary["cases"]):
        folder = output / case["id"]
        folder.mkdir(exist_ok=True)
        panels = []
        originals = native_frames(case, native_root / case["id"])[1] if result["frames"] else []
        for reference in case["resolvedFrames"]:
            i = reference["index"]
            ref = reference["reference"]
            require(digest(ref["resolvedPath"]) == ref["sha256"], "Reference changed during report generation")
            shutil.copyfile(ref["resolvedPath"], folder / f"reference-{i:04d}.png")
            native_html, difference_html, measured = "<p>Native evidence unavailable.</p>", "<p>No measured difference.</p>", ""
            if i < len(result["frames"]):
                actual = originals[i]
                shutil.copyfile(actual["path"], folder / f"native-{i:04d}.png")
                diff = ImageChops.difference(png(ref["resolvedPath"]).convert("RGBa"), png(actual["path"]).convert("RGBa"))
                # RGB display of maximum premultiplied RGB/alpha error, including invisible-color correctness.
                channels = diff.split()
                maximum = channels[0]
                for channel in channels[1:]:
                    maximum = ImageChops.lighter(maximum, channel)
                maximum.point(lambda x: min(255, x * 4)).convert("RGB").save(folder / f"difference-{i:04d}.png")
                native_html = f'<img src="native-{i:04d}.png" alt="Native Metal frame {i}">'
                difference_html = f'<img src="difference-{i:04d}.png" alt="Maximum premultiplied channel difference amplified four times">'
                values = result["frames"][i]
                rows = []
                for gate in values["gates"]:
                    rows.append(f'<tr><td>{html.escape(gate["name"])}</td><td>{gate["actual"]}</td><td>{gate["maximum"]}</td><td>{"PASS" if gate["pass"] else "FAIL"}</td></tr>')
                measured = '<table><tr><th>Measurement</th><th>Observed</th><th>Limit</th><th>Gate</th></tr>' + ''.join(rows) + '</table>'
            elif case["expectation"] == "blocked":
                native_html = ("<p>Conversion blocked as declared. No native pixels rendered.</p>" if result["status"] == "blocked-as-expected"
                               else "<p>Blocked conversion has invalid evidence. See the failure above.</p>")
            panels.append(f'<section><h2>Frame {i} · t = {reference["time"]!r} s</h2><div class="grid"><figure><img src="reference-{i:04d}.png" alt="Independent Figma reference"><figcaption>Original Figma export</figcaption></figure><figure>{native_html}<figcaption>Native Metal</figcaption></figure><figure>{difference_html}<figcaption>Maximum channel error ×4</figcaption></figure></div>{measured}</section>')
        explanation = "Static source artwork." if case["coverage"] == "static" else ("Source endpoint states only. No intermediate prototype playback was sampled." if case["coverage"] == "endpoint-states" else "Independent timeline samples at the listed timestamps; continuous playback between them is outside this measurement.")
        errors = f'<p class="bad">{html.escape(result.get("error", ""))}</p>'
        blockers = f'<pre>{html.escape(json.dumps(result.get("expectedErrorCodes", []), indent=2))}</pre>' if case["expectation"] == "blocked" else ""
        page = f'<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>{html.escape(case["id"])} — Mettle comparison</title><style>{STYLE}</style><a href="../index.html">All cases</a><h1>{html.escape(case["id"])}</h1><p>Status: <strong>{html.escape(result["status"])}</strong>. {explanation}</p><p>Viewport: <code>{html.escape(json.dumps(case["viewport"]))}</code>. Document SHA256: <code>{case["document"]["sha256"]}</code>.</p>{attribution}{errors}{blockers}{"".join(panels)}</html>'
        (folder / "index.html").write_text(page)
        links.append(f'<tr><td><a href="{case["id"]}/index.html">{case["id"]}</a></td><td>{case["coverage"]}</td><td>{result["status"]}</td><td>{len(result["frames"])}</td></tr>')
    (output / "comparison.json").write_text(json.dumps(summary, indent=2, allow_nan=False) + "\n")
    heading = "Source frames passed the pixel gates" if summary["pixelPass"] is True else "Native pixel verification incomplete or failed"
    page = f'<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>Mettle Community comparison</title><style>{STYLE}</style><h1>{heading}</h1><p>{summary["comparedCases"]} of {summary["renderCases"]} render cases compared; {summary["expectedBlockedCases"]} declared exporter blockers confirmed. <strong>Endpoint-state matches do not verify intermediate motion.</strong></p>{attribution}<p><a href="comparison.json">Complete measurements and evidence hashes</a></p><table><tr><th>Case</th><th>Reference coverage</th><th>Status</th><th>Measured frames</th></tr>{"".join(links)}</table><p>{html.escape(" ".join(summary["limitations"]))}</p></html>'
    (output / "index.html").write_text(page)


def render_native(prepared, executable, native_root, raster_scale=1):
    """Run the native CLI with exact times; no source image is an input."""
    executable = executable.resolve()
    require(integer(raster_scale, "render raster scale", 1, 2) in (1, 2), "Raster scale must be 1 or 2")
    require(executable.is_file(), f"Missing native renderer executable {executable}")
    native_root = native_root.resolve()
    require(not native_root.is_relative_to(prepared["root"]) and not prepared["root"].is_relative_to(native_root),
            "Native output directory must be separate from source fixtures")
    jobs = [case for case in prepared["cases"] if case["expectation"] == "render"]
    require(all(not (native_root / case["id"]).exists() for case in jobs), "Native output already exists; choose a fresh run directory")
    native_root.mkdir(parents=True, exist_ok=True)
    for case in jobs:
        times = ",".join(repr(frame["time"]) for frame in case["resolvedFrames"])
        subprocess.run([str(executable), "frames", str(case["documentPath"]), "--scene", str(case["sceneIndex"]),
                        "--width", str(case["viewport"]["width"]), "--height", str(case["viewport"]["height"]),
                        "--loop", "once", "--times", times, "--raster-scale", str(raster_scale),
                        "--output", str(native_root / case["id"])], check=True)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--corpus", type=Path, default=DEFAULT_CORPUS)
    parser.add_argument("--native", type=Path, default=ROOT / "artifacts/community/native")
    parser.add_argument("--output", type=Path, default=ROOT / "artifacts/community/report")
    parser.add_argument("--check-sources", action="store_true", help="Check source/compile integrity only; no native pixel claim")
    parser.add_argument("--render-with", type=Path, help="Native mettle CLI to run before comparison (requires an Apple Metal device)")
    parser.add_argument("--raster-scale", type=int, choices=(1, 2),
                        help="Render at this scale and require matching manifest quality; rendering defaults to 1")
    args = parser.parse_args(argv)
    try:
        prepared = prepare(args.corpus)
        if args.check_sources:
            require(args.render_with is None and args.raster_scale is None, "--check-sources cannot request native rendering settings")
            print(json.dumps({"sourceIntegrityPass": True, "cases": len(prepared["cases"]), "nativePixels": "not-run", "motionPlaybackVerified": False}))
            return 0
        if args.render_with:
            render_native(prepared, args.render_with, args.native, args.raster_scale or 1)
        summary = compare(prepared, args.native, args.raster_scale)
        write_report(prepared, summary, args.native, args.output)
        print(json.dumps({key: summary[key] for key in ("pass", "pixelPass", "renderCases", "comparedCases", "expectedBlockedCases", "motionPlaybackVerified")}, indent=2))
        failed = [{"case": case["id"], "time": frame["time"],
                   "gates": [gate for gate in frame["gates"] if not gate["pass"]]}
                  for case in summary["cases"] for frame in case["frames"] if not frame["pass"]]
        if failed:
            print(json.dumps({"failedPixelGates": failed}, indent=2))
        print(f"Report: {args.output / 'index.html'}")
        return 0 if summary["pass"] else 1
    except (EvidenceError, OSError, subprocess.CalledProcessError, KeyError, TypeError) as error:
        print(f"Comparison evidence failed: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
