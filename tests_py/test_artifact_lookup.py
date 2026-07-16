import sys
import os
import hashlib
import json
import tempfile
import time
import unittest
from pathlib import Path

from openpyxl import Workbook

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "reporting"))

from artifact_lookup import (  # noqa: E402
    filename_has_point_token,
    latest_file_patterns,
    latest_point_image_patterns,
    resolve_output_dirs,
)
from build_monthly_report import build_bearing_section  # noqa: E402
from analysis_manifest import (  # noqa: E402
    manifest_key_for_dir,
    pinned_analysis_manifest_scope,
    pinned_derived_artifact_manifest_scope,
)


class TestArtifactLookup(unittest.TestCase):
    def test_psd_directories_map_to_spectrum_modules_before_broad_hints(self):
        self.assertEqual(
            manifest_key_for_dir("PSD_备查/ZDCQG-01"),
            "accel_spectrum",
        )
        self.assertEqual(
            manifest_key_for_dir("PSD_备查_索力加速度/SLCGQ-01"),
            "cable_accel_spectrum",
        )

    def test_strict_wind_summary_does_not_inherit_figure_role(self):
        for recorded_role in ("summary", "wind_rose"):
            with self.subTest(recorded_role=recorded_role), tempfile.TemporaryDirectory() as td:
                root = Path(td)
                configured_dir = "风速风向结果/风玫瑰"
                folder = root / "风速风向结果" / "风玫瑰"
                folder.mkdir(parents=True)
                point_id = "CSFSY-01-K16-GD-A20"
                summary = folder / (
                    f"{point_id}_windrose_2026-05-01_2026-05-31_summary.txt"
                )
                summary.write_text("平均风速: 1.00 m/s", encoding="utf-8")
                manifest = root / "analysis.json"
                manifest.write_text(
                    json.dumps(
                        {
                            "module_results": [
                                {
                                    "key": "wind",
                                    "artifacts": [
                                        {
                                            "kind": "summary",
                                            "role": recorded_role,
                                            "path": str(summary),
                                            "exists": True,
                                            "bytes": summary.stat().st_size,
                                            "sha256": hashlib.sha256(
                                                summary.read_bytes()
                                            ).hexdigest().upper(),
                                        }
                                    ],
                                }
                            ]
                        },
                        ensure_ascii=False,
                    ),
                    encoding="utf-8",
                )
                manifest_hash = hashlib.sha256(manifest.read_bytes()).hexdigest().upper()

                with pinned_analysis_manifest_scope(
                    manifest,
                    manifest_hash,
                    require_source_provenance=True,
                    result_root=root,
                ):
                    selected = latest_file_patterns(
                        root,
                        configured_dir,
                        [f"{point_id}_windrose_*_summary.txt"],
                        point_id=point_id,
                        point_token_strict=True,
                        kind="summary",
                    )

                self.assertEqual(selected.path, summary.resolve())
                self.assertEqual(selected.debug["source"], "analysis_manifest")

    def test_strict_manifest_rejects_artifact_outside_result_root(self):
        with tempfile.TemporaryDirectory() as td:
            base = Path(td)
            root = base / "result"
            root.mkdir()
            configured_dir = "\u65f6\u7a0b\u66f2\u7ebf_\u52a0\u901f\u5ea6"
            outside_dir = base / configured_dir
            outside_dir.mkdir()
            outside = outside_dir / "A1.jpg"
            outside.write_bytes(b"outside")
            manifest = root / "analysis.json"
            manifest.write_text(json.dumps({
                "module_results": [{
                    "key": "acceleration",
                    "artifacts": [{
                        "kind": "figure",
                        "path": str(outside),
                        "exists": True,
                        "bytes": outside.stat().st_size,
                        "sha256": hashlib.sha256(outside.read_bytes()).hexdigest().upper(),
                    }],
                }],
            }), encoding="utf-8")
            manifest_hash = hashlib.sha256(manifest.read_bytes()).hexdigest().upper()

            with pinned_analysis_manifest_scope(
                manifest, manifest_hash, require_source_provenance=True, result_root=root
            ):
                with self.assertRaisesRegex(ValueError, "outside result_root"):
                    latest_file_patterns(root, configured_dir, ["A1.jpg"], kind="figure")

    def test_strict_manifest_rejects_changed_artifact_size(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            configured_dir = "\u65f6\u7a0b\u66f2\u7ebf_\u52a0\u901f\u5ea6"
            folder = root / configured_dir
            folder.mkdir()
            image = folder / "A1.jpg"
            image.write_bytes(b"original")
            manifest = root / "analysis.json"
            manifest.write_text(json.dumps({
                "module_results": [{
                    "key": "acceleration",
                    "artifacts": [{
                        "kind": "figure",
                        "path": str(image),
                        "exists": True,
                        "bytes": image.stat().st_size,
                        "sha256": hashlib.sha256(image.read_bytes()).hexdigest().upper(),
                    }],
                }],
            }), encoding="utf-8")
            manifest_hash = hashlib.sha256(manifest.read_bytes()).hexdigest().upper()
            image.write_bytes(b"tampered-longer")

            with pinned_analysis_manifest_scope(
                manifest, manifest_hash, require_source_provenance=True, result_root=root
            ):
                with self.assertRaisesRegex(ValueError, "size mismatch"):
                    latest_file_patterns(root, configured_dir, ["A1.jpg"], kind="figure")

    def test_tilt_alias_maps_to_tilt_module(self):
        self.assertEqual(manifest_key_for_dir("\u65f6\u7a0b\u66f2\u7ebf_\u503e\u659c"), "tilt")

    def test_strict_lookup_accepts_only_hash_verified_derived_artifact(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            folder = root / "\u7d22\u529b\u65f6\u7a0b\u56fe"
            folder.mkdir()
            approved = folder / "CableForce_CS4_20260401_20260630.jpg"
            unapproved = folder / "CableForce_CS5_20260401_20260630.jpg"
            approved.write_bytes(b"approved")
            unapproved.write_bytes(b"unapproved")
            analysis = root / "analysis.json"
            analysis.write_text(json.dumps({"module_results": []}), encoding="utf-8")
            analysis_hash = hashlib.sha256(analysis.read_bytes()).hexdigest().upper()
            sidecar = root / "derived.json"
            sidecar.write_text(json.dumps({
                "schema_version": 1,
                "manifest_type": "derived_artifact_manifest",
                "result_root": str(root),
                "analysis_manifest": {"path": str(analysis), "sha256": analysis_hash},
                "artifacts": [{
                    "kind": "figure",
                    "role": "cable_force",
                    "path": str(approved),
                    "bytes": approved.stat().st_size,
                    "sha256": hashlib.sha256(approved.read_bytes()).hexdigest().upper(),
                }],
            }), encoding="utf-8")
            sidecar_hash = hashlib.sha256(sidecar.read_bytes()).hexdigest().upper()

            with pinned_analysis_manifest_scope(
                analysis, analysis_hash, require_source_provenance=True, result_root=root
            ):
                with pinned_derived_artifact_manifest_scope(
                    sidecar, sidecar_hash, require_source_provenance=True
                ):
                    selected = latest_file_patterns(
                        root, "\u7d22\u529b\u65f6\u7a0b\u56fe", ["CableForce_CS4_*.jpg"], kind="figure"
                    )
                    blocked = latest_file_patterns(
                        root, "\u7d22\u529b\u65f6\u7a0b\u56fe", ["CableForce_CS5_*.jpg"], kind="figure"
                    )

            self.assertEqual(selected.path, approved.resolve())
            self.assertEqual(selected.debug["source"], "derived_artifact_manifest")
            self.assertIsNone(blocked.path)
            self.assertEqual(blocked.debug["source"], "pinned_analysis_manifest")

    def test_strict_pinned_manifest_disables_latest_and_filesystem_fallback(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            folder = root / "时程曲线_加速度"
            folder.mkdir()
            pinned_image = folder / "A1_pinned.jpg"
            unlisted_image = folder / "A2_newer.jpg"
            pinned_image.write_text("pinned", encoding="utf-8")
            unlisted_image.write_text("unlisted", encoding="utf-8")
            pinned_manifest = root / "analysis_manifest_pinned.json"
            pinned_manifest.write_text(json.dumps({
                "module_results": [{
                    "key": "acceleration",
                    "artifacts": [{
                        "kind": "figure",
                        "path": str(pinned_image),
                        "exists": True,
                        "bytes": pinned_image.stat().st_size,
                        "sha256": hashlib.sha256(pinned_image.read_bytes()).hexdigest().upper(),
                    }],
                }],
            }), encoding="utf-8")
            newer_manifest = root / "run_logs" / "analysis_manifest_newer.json"
            newer_manifest.parent.mkdir()
            newer_manifest.write_text(json.dumps({
                "module_results": [{
                    "key": "acceleration",
                    "artifacts": [{"kind": "figure", "path": str(unlisted_image)}],
                }],
            }), encoding="utf-8")
            manifest_hash = hashlib.sha256(pinned_manifest.read_bytes()).hexdigest().upper()

            with pinned_analysis_manifest_scope(
                pinned_manifest,
                manifest_hash,
                require_source_provenance=True,
                result_root=root,
            ):
                selected = latest_file_patterns(
                    root,
                    "时程曲线_加速度",
                    ["A1*.jpg"],
                    kind="figure",
                )
                blocked = latest_file_patterns(
                    root,
                    "时程曲线_加速度",
                    ["A2*.jpg"],
                    use_manifest=False,
                    kind="figure",
                )

            self.assertEqual(selected.path, pinned_image)
            self.assertEqual(selected.debug["manifest"], str(pinned_manifest.resolve()))
            self.assertIsNone(blocked.path)
            self.assertEqual(blocked.debug["source"], "pinned_analysis_manifest")

    def test_point_token_does_not_match_prefix_collision(self):
        self.assertTrue(filename_has_point_token(Path("CS1_time.jpg"), "CS1"))
        self.assertFalse(filename_has_point_token(Path("CS12_time.jpg"), "CS1"))

    def test_latest_point_image_uses_strict_point_token_for_filesystem(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            folder = root / "figs"
            folder.mkdir()
            wrong = folder / "CS12_time.jpg"
            right = folder / "CS1_time.jpg"
            wrong.write_text("wrong", encoding="utf-8")
            right.write_text("right", encoding="utf-8")
            result = latest_point_image_patterns(root, "figs", "CS1", ["CS1*.jpg", "CS12*.jpg"])
            self.assertEqual(result.path, right.resolve())
            self.assertTrue(result.debug["rejected_prefix_collisions"])

    def test_latest_point_image_rejects_manifest_prefix_collision(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            folder = root / "时程曲线_索力加速度"
            folder.mkdir()
            right = folder / "CS1_time.jpg"
            wrong = folder / "CS12_time.jpg"
            right.write_text("right", encoding="utf-8")
            wrong.write_text("wrong", encoding="utf-8")
            now = time.time()
            os.utime(right, (now - 10, now - 10))
            os.utime(wrong, (now, now))
            run_logs = root / "run_logs"
            run_logs.mkdir()
            manifest = {
                "schema_version": 2,
                "module_results": [
                    {
                        "key": "cable_accel",
                        "artifacts": [
                            {"kind": "figure", "role": "time_history", "path": str(right)},
                            {"kind": "figure", "role": "time_history", "path": str(wrong)},
                        ],
                    }
                ],
            }
            (run_logs / "analysis_manifest_1.json").write_text(
                __import__("json").dumps(manifest), encoding="utf-8"
            )

            result = latest_point_image_patterns(
                root,
                "时程曲线_索力加速度",
                "CS1",
                ["CS1_*.jpg", "CS12_*.jpg"],
            )

            self.assertEqual(result.path, right.resolve())
            self.assertEqual(result.debug["source"], "analysis_manifest")

    def test_latest_file_patterns_prefers_manifest_when_available(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            folder = root / "时程曲线_加速度"
            folder.mkdir()
            old = folder / "A1_old.jpg"
            new = folder / "A1_new.jpg"
            old.write_text("old", encoding="utf-8")
            new.write_text("new", encoding="utf-8")
            now = time.time()
            os.utime(old, (now - 10, now - 10))
            os.utime(new, (now, now))
            run_logs = root / "run_logs"
            run_logs.mkdir()
            manifest = {
                "schema_version": 2,
                "module_results": [
                    {
                        "key": "acceleration",
                        "artifacts": [
                            {"kind": "figure", "role": "time_history", "path": str(old)},
                            {"kind": "figure", "role": "time_history", "path": str(new)},
                        ],
                    }
                ],
            }
            (run_logs / "analysis_manifest_1.json").write_text(__import__("json").dumps(manifest), encoding="utf-8")
            result = latest_file_patterns(root, "时程曲线_加速度", ["A1*.jpg"], kind=None)
            self.assertEqual(result.path, new)
            self.assertEqual(result.debug["source"], "analysis_manifest")

    def test_resolve_output_dirs_skips_venv_when_recursive(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            good = root / "a" / "plots"
            bad = root / ".venv" / "plots"
            good.mkdir(parents=True)
            bad.mkdir(parents=True)
            dirs = resolve_output_dirs(root, "plots")
            self.assertIn(good.resolve(), dirs)
            self.assertNotIn(bad.resolve(), dirs)

    def test_bearing_section_accepts_raw_orig_filename_without_extra_suffix(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            stats = root / "stats"
            image_dir = root / "bearing_raw"
            assets = root / "assets"
            stats.mkdir()
            image_dir.mkdir()
            assets.mkdir()

            wb = Workbook()
            ws = wb.active
            ws.append(["PointID", "OrigMin_mm", "OrigMax_mm", "FiltMin_mm", "FiltMax_mm"])
            ws.append(["Z11-1", -1.0, 1.0, -0.5, 0.5])
            wb.save(stats / "bearing_displacement_stats.xlsx")

            image = image_dir / "BearingDisp_Z11-1_20260401_20260630_Orig.jpg"
            image.write_bytes(b"not-a-real-image")

            cfg = {
                "points": {"bearing_displacement": ["Z11-1"]},
                "plot_styles": {"bearing_displacement": {"raw_output_dir": "bearing_raw"}},
            }

            section = build_bearing_section(cfg, stats, None, root, assets)

            self.assertEqual(Path(section["images"][0]["path"]), image)
            self.assertEqual(Path(section["image_lookup"][0]["selected_file"]), image)


if __name__ == "__main__":
    unittest.main()
