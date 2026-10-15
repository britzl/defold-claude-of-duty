"""Regression tests for provenance: stale/failed evidence must never pass silently."""
import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("parity_baseline", ROOT / "tools/parity_baseline.py")
baseline = importlib.util.module_from_spec(spec)
spec.loader.exec_module(baseline)


class ParityBaselineTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "src").mkdir()
        (self.root / "src/main.js").write_text("source")
        (self.root / "package-lock.json").write_text("{}")
        self.roots = {name: self.root for name in ("defold", "threejs", "kaigen")}
        self.catalog = {"version": 12, "shots": [
            {"id": "sunset", "position": [0, 1, 0], "target": [0, 1, -1], "fov": 65, "lighting": "sunset"},
            {"id": "weapon_fire"},
        ]}
        self.image = self.root / "sunset.png"
        self.image.write_bytes(b"test image payload")
        self.manifest = self.root / "manifest.json"
        self.report = {"engine": "threejs", "catalog_version": 12,
            "source_sha256": baseline.legacy_fingerprint("threejs", self.root),
            "shots": {"sunset": {"status": "captured", "image": self.image.name,
                "sha256": baseline.sha(self.image.read_bytes()), "hour": 19.200000000000003,
                "camera": {"level_position": [0, 1, 0], "level_target": [0, 1, -1], "vertical_fov": 65,
                           "position": [0, 1, 0], "quaternion": [0, 0, 0, 1]},
                "level_to_world_matrix": [1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1],
                "weapon_id": None, "deterministic": True, "quality": {"taa": True}, "exposure": {"exposure": 1}}}}

    def receipt(self, report=None):
        self.manifest.write_text(json.dumps(report or self.report))
        return baseline.capture_receipt(self.manifest, self.roots, self.catalog)

    def test_partial_and_pending_captures_never_claim_complete_repeatability(self):
        receipt = self.receipt()
        self.assertFalse(receipt["all_catalog_shots_captured_and_repeated"])
        self.assertEqual(receipt["reported_repeat_identical"], [])
        self.assertEqual(receipt["not_run"], ["weapon_fire"])
        self.report["shots"]["weapon_fire"] = {"status": "pending", "reason": "No event timeline"}
        receipt = self.receipt()
        self.assertEqual(receipt["pending"], {"weapon_fire": "No event timeline"})
        self.assertFalse(receipt["all_catalog_shots_captured_and_repeated"])

    def test_failed_or_stale_source_and_catalogue_are_rejected(self):
        for patch in ({"error": "server failed"}, {"source_sha256": "stale"}, {"catalog_version": 11}):
            with self.subTest(patch=patch), self.assertRaises(ValueError):
                self.receipt({**self.report, **patch})
        self.report["shots"]["sunset"]["status"] = "failed"
        with self.assertRaisesRegex(ValueError, "Failed capture"):
            self.receipt()

    def test_tampered_pixels_and_wrong_camera_or_weapon_are_rejected(self):
        for patch in ({"sha256": "tampered"}, {"hour": 16.5}, {"weapon_id": "rifle"}, {"camera": {}}, {"deterministic": False}):
            report = copy.deepcopy(self.report)
            report["shots"]["sunset"].update(patch)
            with self.subTest(patch=patch), self.assertRaises(ValueError):
                self.receipt(report)

    def test_source_lock_detects_content_rename_and_audio_changes(self):
        (self.root / "audio").mkdir()
        sample = self.root / "audio/shot.wav"
        sample.write_bytes(b"sound one")
        scopes = ("src", "audio")
        first = baseline.fingerprint(self.root, scopes)
        sample.write_bytes(b"sound two")
        second = baseline.fingerprint(self.root, scopes)
        self.assertNotEqual(first["sha256"], second["sha256"])
        sample.rename(sample.with_name("reload.wav"))
        self.assertNotEqual(second["sha256"], baseline.fingerprint(self.root, scopes)["sha256"])
        self.assertIsNone(baseline.revision(self.root))

    def test_actual_camera_must_match_echoed_request(self):
        for field, value in (("position", [0, 2, 0]), ("quaternion", [0, 1, 0, 0])):
            report = copy.deepcopy(self.report)
            report["shots"]["sunset"]["camera"][field] = value
            with self.subTest(field=field), self.assertRaisesRegex(ValueError, "Actual camera"):
                self.receipt(report)

    def test_failed_run_requires_explicit_partial_import_and_retains_failure(self):
        self.report["error"] = "late browser load timeout"
        self.report["shots"]["weapon_fire"] = {"status": "failed", "reason": "load timeout"}
        self.manifest.write_text(json.dumps(self.report))
        receipt = baseline.capture_receipt(self.manifest, self.roots, self.catalog, allow_partial=True)
        self.assertEqual(receipt["captured"], ["sunset"])
        self.assertEqual(receipt["failed"], {"weapon_fire": "load timeout"})
        self.assertEqual(receipt["run_error"], "late browser load timeout")
        self.assertFalse(receipt["all_catalog_shots_captured_and_repeated"])

    def test_scenario_references_and_adaptation_gates_must_resolve(self):
        scenario = {"id": "scene", "feature": "Scene", "procedure": "Inspect", "expect": "Visible", "current": "partial",
                    "references": ["threejs:src/main.js"], "coverage": ["src/main.js"]}
        contract = {"schema_version": 1, "scenarios": [scenario], "adaptations": [{"gate": "scene"}]}
        self.assertEqual(baseline.validate_contract(contract, self.roots), 1)
        contract["adaptations"][0]["gate"] = "absent"
        with self.assertRaisesRegex(ValueError, "Unknown adaptation gate"):
            baseline.validate_contract(contract, self.roots)
        contract["adaptations"] = []
        scenario["references"] = ["kaigen:src/absent.c"]
        with self.assertRaisesRegex(ValueError, "Missing reference"):
            baseline.validate_contract(contract, self.roots)


if __name__ == "__main__":
    unittest.main()
