#!/usr/bin/env python3
"""Adversarial tests of evidence validation and measurements, not GPU goldens.

Every image and 'native' manifest below is a temporary synthetic measurement
fixture. They are never stored in the Community corpus or claimed as renders.
"""
import copy
import json
from pathlib import Path
import shutil
import tempfile
import unittest
from unittest.mock import patch

from PIL import Image, ImageDraw
from compare_corpus import EvidenceError, compare, digest, prepare, render_native, write_report


class CorpusComparisonTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.evidence = self.root / "evidence"
        self.evidence.mkdir()
        self.native = self.root / "native"
        self.output = self.root / "report"

    def tearDown(self):
        self.temporary.cleanup()

    def dump(self, path, value):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(value, indent=2) + "\n")

    def artifact(self, path):
        return {"path": str(path.relative_to(self.evidence)), "sha256": digest(path)}

    def fixture(self, references=None, actual=None, times=None, blocked=False, background=None):
        if references is None:
            image = Image.new("RGBA", (16, 16))
            ImageDraw.Draw(image).rectangle((4, 4, 11, 11), fill=(180, 70, 30, 255))
            references = [image]
        actual = actual or references
        times = times or ([0] if len(references) == 1 else [0, 0.20000000298023224])
        width, height = references[0].size
        viewport = {"x": 0, "y": 0, "width": width, "height": height}
        snapshots, fixtures = [], []
        for i, reference in enumerate(references):
            snapshot = {"id": f"node-{i}", "testOnly": "Synthetic measurement fixture"}
            snapshots.append(snapshot)
            snapshot_path = self.evidence / f"state-{i}.snapshot.json"
            png_path = self.evidence / f"reference-{i}.png"
            self.dump(snapshot_path, snapshot)
            reference.save(png_path)
            fixtures.append({"slug": f"state-{i}", "instanceId": snapshot["id"], "sourceFrameId": f"frame-{i}",
                             "snapshot": self.artifact(snapshot_path),
                             "reference": {**self.artifact(png_path), "width": width, "height": height,
                                           "sourceFrameId": f"frame-{i}", "method": "figma.exportAsync/png", "viewport": viewport}})
        provenance = {"format": "mettle-community-provenance", "version": 1,
                      "communityURL": "https://www.figma.com/community/file/0/synthetic-measurement-tests-only",
                      "captureFileKey": "synthetic-test-no-figma-capture", "capturedDate": "2026-10-08",
                      "fixtures": fixtures, "testOnly": "All images and metadata in this temporary directory are synthetic."}
        provenance_path = self.evidence / "provenance.json"
        self.dump(provenance_path, provenance)
        source = {"format": "mettle-source", "version": 1, "mode": "static" if len(references) == 1 else "transition",
                  "nodes": snapshots, "options": {"viewport": viewport},
                  "provenance": {"sourceManifest": self.artifact(provenance_path)}}
        source_path = self.evidence / "source.json"
        self.dump(source_path, source)
        document = {"format": "figma-metal", "version": 2,
                    "scenes": [{"width": width, "height": height, "duration": times[-1], "loop": "once", "root": {}}],
                    "provenance": {"sourceCaptureSHA256": digest(source_path)},
                    "diagnostics": [{"severity": "error", "code": "PATH_CHANGE", "nodeID": "node-0"}] if blocked else []}
        self.document_path = self.evidence / "document.figmetal.json"
        self.dump(self.document_path, document)
        case = {"id": "measurement", "expectation": "blocked" if blocked else "render",
                "coverage": "static" if len(references) == 1 else "endpoint-states", "sourceFixtures": [f"state-{i}" for i in range(len(references))],
                "source": self.artifact(source_path), "document": self.artifact(self.document_path), "sceneIndex": 0,
                "duration": times[-1], "viewport": viewport, "loop": "once",
                "referenceFrames": [{"index": i, "time": time, "fixture": f"state-{i}"} for i, time in enumerate(times)],
                "foreground": {"backgroundRGBA": background or [0, 0, 0, 0], "threshold": 8},
                "regions": [{"id": "content", "rect": [0, 0, width, height]}]}
        if blocked:
            case["expectedErrorCodes"] = ["PATH_CHANGE"]
        self.corpus = {"format": "mettle-comparison-corpus", "version": 1, "provenance": self.artifact(provenance_path),
                       "thresholds": {"whole": {"rgbMAE": 2, "alphaMAE": 3}, "foreground": {"rgbMAE": 4, "alphaMAE": 6},
                                      "regions": {"rgbMAE": 4, "alphaMAE": 6}, "boundsMaxPixels": 2}, "cases": [case]}
        self.corpus_path = self.evidence / "corpus.json"
        self.save_corpus()
        self.native_case = self.native / "measurement"
        self.manifest_path = self.native_case / "manifest.json"
        if not blocked:
            self.native_case.mkdir(parents=True)
            entries = []
            for i, (image, time) in enumerate(zip(actual, times)):
                path = self.native_case / f"{i:04d}.png"
                image.save(path)
                entries.append({"index": i, "time": time, "file": path.name, "sha256": digest(path)})
            self.manifest = {"format": "mettle-frames", "version": 1, "backend": "Metal",
                             "sourceSHA256": digest(self.document_path), "sceneIndex": 0, "sceneDuration": times[-1],
                             "loop": "once", "width": width, "height": height,
                             "device": "Synthetic measurement test fixture; not a GPU result", "frames": entries}
            self.save_native()
        return case

    def save_corpus(self):
        self.dump(self.corpus_path, self.corpus)

    def save_native(self):
        self.dump(self.manifest_path, self.manifest)

    def result(self):
        return compare(prepare(self.corpus_path), self.native)

    def test_identical_endpoint_measurements_preserve_exact_times_without_claiming_motion(self):
        image = Image.new("RGBA", (8, 8), (25, 50, 100, 255))
        self.fixture([image, image])
        result = self.result()
        self.assertTrue(result["pass"])
        self.assertTrue(result["pixelPass"])
        self.assertFalse(result["motionPlaybackVerified"])
        self.assertEqual([frame["time"] for frame in result["cases"][0]["frames"]], [0, 0.20000000298023224])

    def test_missing_native_evidence_is_a_failure(self):
        self.fixture()
        shutil.rmtree(self.native)
        result = self.result()
        self.assertFalse(result["pass"])
        self.assertFalse(result["pixelPass"])
        self.assertEqual(result["comparedCases"], 0)

    def test_native_manifest_invariants_are_not_silently_ignored(self):
        image = Image.new("RGBA", (8, 8), (25, 50, 100, 255))
        self.fixture([image, image])
        original = copy.deepcopy(self.manifest)
        changes = [("backend", "CPU"), ("sourceSHA256", "0" * 64), ("sceneIndex", 1), ("sceneDuration", 1),
                   ("loop", "loop"), ("width", 9), ("height", 9), ("device", ""), ("format", "generic-images")]
        for field, value in changes:
            with self.subTest(field=field):
                self.manifest = {**copy.deepcopy(original), field: value}
                self.save_native()
                self.assertFalse(self.result()["pass"])

    def test_frame_count_order_indices_times_and_filenames_are_checked(self):
        image = Image.new("RGBA", (8, 8), (25, 50, 100, 255))
        self.fixture([image, image])
        original = copy.deepcopy(self.manifest)
        variants = [[], original["frames"][:1], list(reversed(original["frames"]))]
        for change in [dict(index=2), dict(time=0), dict(time=float("nan")), dict(file="0000.png"), dict(file="../reference-1.png")]:
            frames = copy.deepcopy(original["frames"])
            frames[1].update(change)
            variants.append(frames)
        for frames in variants:
            with self.subTest(frames=frames):
                self.manifest = {**copy.deepcopy(original), "frames": frames}
                self.save_native()
                self.assertFalse(self.result()["pass"])

    def test_stale_extra_native_png_and_missing_png_fail(self):
        self.fixture()
        shutil.copyfile(self.native_case / "0000.png", self.native_case / "stale.png")
        self.assertFalse(self.result()["pass"])
        (self.native_case / "stale.png").unlink()
        (self.native_case / "0000.png").unlink()
        self.assertFalse(self.result()["pass"])

    def test_native_pixels_are_hash_checked_even_when_dimensions_match(self):
        self.fixture()
        Image.new("RGBA", (16, 16), (255, 0, 0, 255)).save(self.native_case / "0000.png")
        self.assertFalse(self.result()["pass"])
        self.assertIn("SHA256 mismatch", self.result()["cases"][0]["error"])

    def test_native_png_dimensions_must_match_its_manifest(self):
        self.fixture()
        path = self.native_case / "0000.png"
        Image.new("RGBA", (17, 16)).save(path)
        self.manifest["frames"][0]["sha256"] = digest(path)
        self.save_native()
        self.assertFalse(self.result()["pass"])

    def test_changed_source_snapshot_is_rejected(self):
        self.fixture()
        (self.evidence / "state-0.snapshot.json").write_text('{"id":"different"}')
        with self.assertRaises(EvidenceError):
            prepare(self.corpus_path)

    def test_changed_reference_png_is_rejected_instead_of_becoming_a_new_golden(self):
        self.fixture()
        Image.new("RGBA", (16, 16)).save(self.evidence / "reference-0.png")
        with self.assertRaises(EvidenceError):
            prepare(self.corpus_path)

    def test_changed_provenance_and_compiled_capture_hash_are_rejected(self):
        self.fixture()
        document = json.loads(self.document_path.read_text())
        document["provenance"]["sourceCaptureSHA256"] = "0" * 64
        self.dump(self.document_path, document)
        self.corpus["cases"][0]["document"] = self.artifact(self.document_path)
        self.save_corpus()
        with self.assertRaises(EvidenceError):
            prepare(self.corpus_path)

    def test_replay_source_must_contain_the_actual_captured_nodes(self):
        self.fixture()
        path = self.evidence / "source.json"
        source = json.loads(path.read_text())
        source["nodes"][0]["id"] = "made-up"
        self.dump(path, source)
        self.corpus["cases"][0]["source"] = self.artifact(path)
        self.save_corpus()
        with self.assertRaises(EvidenceError):
            prepare(self.corpus_path)

    def test_tiny_missing_foreground_cannot_hide_in_the_background_average(self):
        image = Image.new("RGBA", (128, 128))
        image.putpixel((50, 50), (255, 255, 255, 255))
        self.fixture([image], [Image.new("RGBA", image.size)])
        result = self.result()
        frame = result["cases"][0]["frames"][0]
        self.assertLess(frame["whole"]["alphaMAE"], 0.02)
        self.assertEqual(frame["foreground"]["alphaMAE"], 255)
        self.assertEqual(frame["foreground"]["pixelCount"], 1)
        self.assertFalse(result["pixelPass"])

    def test_opaque_background_also_uses_foreground_gates(self):
        image = Image.new("RGBA", (128, 128), (255, 255, 255, 255))
        image.putpixel((50, 50), (0, 0, 0, 255))
        self.fixture([image], [Image.new("RGBA", image.size, (255, 255, 255, 255))], background=[255, 255, 255, 255])
        result = self.result()
        frame = result["cases"][0]["frames"][0]
        self.assertLess(frame["whole"]["rgbMAE"], 0.02)
        self.assertEqual(frame["foreground"]["rgbMAE"], 255)
        self.assertFalse(result["pixelPass"])

    def test_foreground_union_includes_spurious_native_geometry(self):
        image = Image.new("RGBA", (64, 64))
        actual = image.copy()
        image.putpixel((4, 4), (255, 0, 0, 255))
        actual.putpixel((60, 60), (0, 0, 255, 255))
        self.fixture([image], [actual])
        frame = self.result()["cases"][0]["frames"][0]
        self.assertEqual(frame["foreground"]["pixelCount"], 2)
        self.assertEqual(frame["boundsError"], 56)

    def test_transparent_rgb_is_not_a_pixel_mismatch(self):
        self.fixture([Image.new("RGBA", (8, 8), (255, 0, 0, 0))], [Image.new("RGBA", (8, 8), (0, 255, 255, 0))])
        self.assertTrue(self.result()["pixelPass"])

    def test_missing_endpoints_and_padded_regions_are_rejected(self):
        image = Image.new("RGBA", (8, 8))
        self.fixture([image, image])
        original = copy.deepcopy(self.corpus)
        for box in [[-1, 0, 8, 8], [0, 0, 9, 8], [4, 4, 2, 2]]:
            self.corpus = copy.deepcopy(original)
            self.corpus["cases"][0]["regions"][0]["rect"] = box
            self.save_corpus()
            with self.assertRaises(EvidenceError):
                prepare(self.corpus_path)
        self.corpus = copy.deepcopy(original)
        self.corpus["cases"][0]["referenceFrames"].pop()
        self.save_corpus()
        with self.assertRaises(EvidenceError):
            prepare(self.corpus_path)

    def test_static_exports_cannot_be_relabelled_as_timeline_frames(self):
        image = Image.new("RGBA", (8, 8))
        self.fixture([image, image])
        self.corpus["cases"][0]["coverage"] = "timeline-frames"
        self.save_corpus()
        with self.assertRaises(EvidenceError):
            prepare(self.corpus_path)

    def test_expected_blocker_is_a_contract_result_with_no_pixel_success(self):
        self.fixture(blocked=True)
        result = self.result()
        self.assertTrue(result["pass"])
        self.assertIsNone(result["pixelPass"])
        self.assertEqual(result["expectedBlockedCases"], 1)
        self.assertEqual(result["comparedCases"], 0)
        self.assertFalse(result["motionPlaybackVerified"])
        write_report(prepare(self.corpus_path), result, self.native, self.output)
        self.assertIn("No native pixels rendered", (self.output / "measurement/index.html").read_text())

    def test_unexpected_blocker_and_rendering_a_blocked_case_fail(self):
        self.fixture(blocked=True)
        self.native_case.mkdir(parents=True)
        Image.new("RGBA", (16, 16)).save(self.native_case / "0000.png")
        self.assertFalse(self.result()["pass"])
        self.corpus["cases"][0]["expectedErrorCodes"] = ["SOMETHING_ELSE"]
        self.save_corpus()
        with self.assertRaises(EvidenceError):
            prepare(self.corpus_path)

    def test_report_preserves_original_png_bytes_and_lists_exact_time(self):
        image = Image.new("RGBA", (8, 8), (25, 50, 100, 255))
        self.fixture([image, image])
        originals = {p: p.read_bytes() for p in self.evidence.glob("*.png")}
        prepared = prepare(self.corpus_path)
        write_report(prepared, compare(prepared, self.native), self.native, self.output)
        for path, original in originals.items():
            self.assertEqual(path.read_bytes(), original)
        self.assertEqual((self.output / "measurement/reference-0000.png").read_bytes(), originals[self.evidence / "reference-0.png"])
        self.assertIn("0.20000000298023224", (self.output / "measurement/index.html").read_text())

    def test_report_cannot_overwrite_source_or_native_evidence(self):
        self.fixture()
        prepared = prepare(self.corpus_path)
        for output in [self.evidence, self.evidence / "report", self.native, self.native / "report", self.root]:
            with self.assertRaises(EvidenceError):
                write_report(prepared, compare(prepared, self.native), self.native, output)

    def test_renderer_receives_the_source_document_and_exact_schedule_only(self):
        image = Image.new("RGBA", (8, 8))
        self.fixture([image, image])
        executable = self.root / "synthetic-executable-never-run"
        executable.touch()
        with patch("compare_corpus.subprocess.run") as run:
            render_native(prepare(self.corpus_path), executable, self.root / "new-native-run")
        args = run.call_args.args[0]
        self.assertIn(str(self.document_path), args)
        self.assertEqual(args[args.index("--times") + 1], "0,0.20000000298023224")
        self.assertEqual(args[args.index("--loop") + 1], "once")
        self.assertFalse(any(value.endswith(".png") for value in args))


if __name__ == "__main__":
    unittest.main()
