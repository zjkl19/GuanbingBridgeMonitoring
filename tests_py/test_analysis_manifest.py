from __future__ import annotations

import json
import hashlib
import sys
import tempfile
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
REPORTING_ROOT = REPO_ROOT / "reporting"
for candidate in (REPO_ROOT, REPORTING_ROOT):
    if str(candidate) not in sys.path:
        sys.path.insert(0, str(candidate))

from reporting.analysis_manifest import (
    analysis_manifest_context,
    find_latest_analysis_manifest,
    load_analysis_manifest,
    manifest_missing_modules,
    manifest_precheck_warnings,
    missing_module_summary_items,
    pinned_analysis_manifest_scope,
    pinned_derived_artifact_manifest_scope,
)


class AnalysisManifestTests(unittest.TestCase):
    def test_strict_scope_rejects_manifest_outside_allowed_result_root(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            root = base / "result"
            root.mkdir()
            outside = base / "analysis.json"
            outside.write_text('{"status":"ok"}', encoding="utf-8")
            outside_hash = hashlib.sha256(outside.read_bytes()).hexdigest().upper()

            with self.assertRaisesRegex(ValueError, "outside result_root"):
                with pinned_analysis_manifest_scope(
                    outside,
                    outside_hash,
                    require_source_provenance=True,
                    result_root=root,
                ):
                    pass

    def test_derived_manifest_requires_path_and_hash_as_a_pair(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            analysis = root / "analysis.json"
            analysis.write_text('{"status":"ok"}', encoding="utf-8")
            analysis_hash = hashlib.sha256(analysis.read_bytes()).hexdigest().upper()

            with pinned_analysis_manifest_scope(
                analysis,
                analysis_hash,
                require_source_provenance=True,
                result_root=root,
            ):
                with self.assertRaisesRegex(ValueError, "provided together"):
                    with pinned_derived_artifact_manifest_scope(
                        None, "A" * 64, require_source_provenance=True
                    ):
                        pass

    def test_derived_artifact_scope_verifies_parent_and_each_file_hash(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            analysis = root / "analysis.json"
            artifact = root / "derived" / "CableForce_CS4.jpg"
            artifact.parent.mkdir()
            analysis.write_text(json.dumps({"status": "ok"}), encoding="utf-8")
            artifact.write_bytes(b"derived")
            analysis_hash = hashlib.sha256(analysis.read_bytes()).hexdigest().upper()
            artifact_hash = hashlib.sha256(artifact.read_bytes()).hexdigest().upper()
            sidecar = root / "derived_manifest.json"
            sidecar.write_text(json.dumps({
                "schema_version": 1,
                "manifest_type": "derived_artifact_manifest",
                "result_root": str(root),
                "analysis_manifest": {"path": str(analysis), "sha256": analysis_hash},
                "artifacts": [{
                    "kind": "figure",
                    "role": "cable_force",
                    "path": str(artifact),
                    "bytes": artifact.stat().st_size,
                    "sha256": artifact_hash,
                }],
            }), encoding="utf-8")
            sidecar_hash = hashlib.sha256(sidecar.read_bytes()).hexdigest().upper()

            with pinned_analysis_manifest_scope(
                analysis, analysis_hash, require_source_provenance=True, result_root=root
            ):
                with pinned_derived_artifact_manifest_scope(
                    sidecar, sidecar_hash, require_source_provenance=True
                ):
                    context = analysis_manifest_context(root)
                    self.assertTrue(context["derived_artifact_manifest"]["available"])
                    self.assertEqual(context["derived_artifact_manifest"]["artifact_count"], 1)

                artifact.write_bytes(b"tampered")
                with self.assertRaisesRegex(ValueError, "artifact SHA-256 mismatch"):
                    with pinned_derived_artifact_manifest_scope(
                        sidecar, sidecar_hash, require_source_provenance=True
                    ):
                        pass

    def test_strict_scope_uses_exact_manifest_and_rejects_hash_mismatch(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            run_logs = root / "run_logs"
            run_logs.mkdir()
            pinned = run_logs / "analysis_manifest_1.json"
            latest = run_logs / "analysis_manifest_2.json"
            pinned.write_text(json.dumps({"status": "ok", "marker": "pinned"}), encoding="utf-8")
            latest.write_text(json.dumps({"status": "ok", "marker": "latest"}), encoding="utf-8")
            expected_hash = hashlib.sha256(pinned.read_bytes()).hexdigest().upper()

            with pinned_analysis_manifest_scope(
                pinned,
                expected_hash,
                require_source_provenance=True,
                result_root=root,
            ):
                context = analysis_manifest_context(root)
                self.assertEqual(context["path"], str(pinned.resolve()))
                self.assertEqual(context["manifest"]["marker"], "pinned")
                self.assertTrue(context["strict_source_provenance"])
                self.assertEqual(context["sha256"], expected_hash)

            with self.assertRaisesRegex(ValueError, "SHA-256 mismatch"):
                with pinned_analysis_manifest_scope(
                    pinned,
                    "0" * 64,
                    require_source_provenance=True,
                    result_root=root,
                ):
                    pass

    def test_latest_manifest_and_missing_modules(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            run_logs = root / "run_logs"
            run_logs.mkdir()
            manifest_path = run_logs / "analysis_manifest_20260101_010101.json"
            manifest_path.write_text(
                json.dumps(
                    {
                        "module_preflight": [
                            {"key": "strain", "label": "strain analysis", "status": "missing", "message": "missing stats"}
                        ],
                        "module_logs": [
                            {"key": "wind", "label": "wind analysis", "status": "fail", "message": "read failed"}
                        ],
                        "module_results": [
                            {"key": "eq", "label": "eq analysis", "status": "skip", "message": "no data"}
                        ],
                        "run_request": {"data_root": "E:/data"},
                        "run_preflight": {"status": "warning"},
                    },
                    ensure_ascii=False,
                ),
                encoding="utf-8",
            )

            self.assertEqual(find_latest_analysis_manifest(root), manifest_path)
            context = analysis_manifest_context(root)
            missing = manifest_missing_modules(context["manifest"])
            self.assertEqual({item["key"] for item in missing}, {"strain", "eq"})
            self.assertEqual(context["run_request"]["data_root"], "E:/data")
            self.assertEqual(context["run_preflight"]["status"], "warning")
            summary = missing_module_summary_items(context)
            self.assertTrue(any("strain analysis" in item for item in summary))
            self.assertTrue(any("eq analysis" in item for item in summary))

    def test_successful_result_suppresses_stale_preflight_missing(self) -> None:
        manifest = {
            "module_preflight": [
                {
                    "key": "strain",
                    "label": "strain analysis",
                    "status": "missing",
                    "exists": False,
                    "message": "old missing state",
                }
            ],
            "module_results": [
                {"key": "strain", "label": "strain analysis", "status": "ok", "message": "rerun succeeded"}
            ],
        }

        self.assertEqual(manifest_missing_modules(manifest), [])

    def test_load_manifest_accepts_utf8_bom(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            manifest_path = Path(tmp) / "analysis_manifest_20260101_010101.json"
            manifest_path.write_text('{"status": "completed"}', encoding="utf-8-sig")

            self.assertEqual(load_analysis_manifest(manifest_path)["status"], "completed")

    def test_manifest_precheck_warnings(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            run_logs = root / "run_logs"
            run_logs.mkdir()
            (run_logs / "analysis_manifest_20260101_010101.json").write_text(
                json.dumps(
                    {
                        "status": "failed",
                        "missing_expected_stats": ["E:/data/stats/strain_stats.xlsx"],
                        "run_preflight": {"warnings": ["WIM input missing for 202601"]},
                        "module_results": [
                            {"key": "strain", "label": "strain analysis", "status": "fail", "message": "read failed"}
                        ],
                    },
                    ensure_ascii=False,
                ),
                encoding="utf-8",
            )

            warnings = manifest_precheck_warnings(root)
            joined = "\n".join(warnings)
            self.assertIn("analysis manifest status is failed", joined)
            self.assertIn("strain analysis", joined)
            self.assertIn("strain_stats.xlsx", joined)
            self.assertIn("WIM input missing", joined)

    def test_missing_manifest_warning(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            warnings = manifest_precheck_warnings(Path(tmp))

            self.assertEqual(len(warnings), 1)
            self.assertIn("analysis manifest not found", warnings[0])


if __name__ == "__main__":
    unittest.main()
