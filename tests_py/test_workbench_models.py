from __future__ import annotations

import json
import re
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path

from workbench.models import JobContext
from workbench.modules import MODULE_SPECS, options_for_modules
from workbench.profiles import load_profiles
from workbench.version import app_version


class WorkbenchModelTests(unittest.TestCase):
    def test_version_uses_single_project_file(self) -> None:
        root = Path(__file__).resolve().parents[1]
        expected = (root / "VERSION").read_text(encoding="utf-8-sig").strip()
        self.assertEqual(app_version(root), expected)

    def test_version_fallback_covers_missing_and_empty_version_file(self) -> None:
        from workbench.version import DEFAULT_VERSION

        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            self.assertEqual(app_version(root), DEFAULT_VERSION)
            (root / "VERSION").write_text("\ufeff\n", encoding="utf-8")
            self.assertEqual(app_version(root), DEFAULT_VERSION)

    def test_profile_catalog_matches_shared_json(self) -> None:
        root = Path(__file__).resolve().parents[1]
        profiles = load_profiles(root)
        raw = json.loads((root / "config" / "bridge_profiles.json").read_text(encoding="utf-8"))
        self.assertEqual([item.bridge_id for item in profiles], [item["bridge_id"] for item in raw["profiles"]])
        self.assertEqual(next(item for item in profiles if item.bridge_id == "zhishan").enabled_modules[0], "strain")
        self.assertTrue(all(item.optional_modules == ("cache_prebuild",) for item in profiles))

    def test_module_options_are_complete_and_reject_unknown_keys(self) -> None:
        options = options_for_modules(["temperature", "acceleration"])
        self.assertEqual(len(options), len(MODULE_SPECS))
        self.assertTrue(options["doTemp"])
        self.assertTrue(options["doAccel"])
        self.assertFalse(options["doWind"])
        self.assertFalse(options["doCachePrebuild"])
        cache_options = options_for_modules(["cache_prebuild"])
        self.assertTrue(cache_options["doCachePrebuild"])
        with self.assertRaisesRegex(ValueError, "Unknown analysis modules"):
            options_for_modules(["not-a-module"])

    def test_all_workbench_modules_have_stable_icons(self) -> None:
        self.assertTrue(all(spec.icon_asset for spec in MODULE_SPECS))
        root = Path(__file__).resolve().parents[1] / "workbench" / "assets" / "module_icons"
        self.assertTrue(all((root / spec.icon_asset).is_file() for spec in MODULE_SPECS))
        expected = {
            "cache_prebuild": "cache-prebuild.svg",
            "lowfreq_sync": "acquisition-sync.svg",
            "temperature": "thermometer.svg",
            "rainfall": "rainfall.svg",
            "gnss": "satellite.svg",
            "wind": "wind.svg",
            "wim": "truck-scale.svg",
            "acceleration": "acceleration.svg",
            "cable_accel": "cable-vibration.svg",
            "accel_spectrum": "spectrum.svg",
            "cable_accel_spectrum": "cable-spectrum.svg",
            "crack": "crack.svg",
            "strain": "strain.svg",
            "dynamic_strain_highpass": "highpass.svg",
            "dynamic_strain_lowpass": "lowpass.svg",
        }
        self.assertEqual({key: next(spec.icon_asset for spec in MODULE_SPECS if spec.key == key)
                          for key in expected}, expected)
        app_assets = root.parent
        for name in ("app_icon.svg", "app_icon.png", "app_icon.ico"):
            self.assertTrue((app_assets / name).is_file(), name)
        self.assertEqual(
            (app_assets / "organization_logo.png").read_bytes(),
            (app_assets.parents[1] / "建科院标志PNG-01.png").read_bytes(),
        )

    def test_python_module_contract_matches_matlab_registry(self) -> None:
        root = Path(__file__).resolve().parents[1]
        source = (root / "+bms" / "+module" / "ModuleRegistry.m").read_text(encoding="utf-8")
        matlab_pairs = [
            (key, option)
            for key, option in re.findall(r"S\('([^']*)','([^']*)'", source)
            if option
        ]
        python_pairs = [(spec.key, spec.option_field) for spec in MODULE_SPECS]
        self.assertEqual(python_pairs, matlab_pairs)

    def test_job_context_round_trip_and_report_gate(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            config = root / "config.json"
            config.write_text('{"project":{"id":"unit"}}', encoding="utf-8")
            data_root = root / "数据"
            data_root.mkdir()
            context = JobContext.create(
                project_root=root,
                bridge_id="unit",
                bridge_name="测试桥",
                data_root=data_root,
                start_date="2026-01-01",
                end_date="2026-01-31",
                config_path=config,
                selected_modules=["temperature"],
                options=options_for_modules(["temperature"]),
                report_type="unit_monthly",
                template_path=None,
                output_dir=data_root / "自动报告",
                now=datetime(2026, 7, 12, 9, 30, tzinfo=timezone.utc),
                job_id="unit_job",
            )
            path = context.write()
            loaded = JobContext.read(path)
            self.assertEqual(loaded.job_id, "unit_job")
            self.assertEqual(loaded.config_sha256, context.config_sha256)
            self.assertEqual(Path(loaded.analysis.request_path).parent, data_root / "run_logs" / "workbench" / "unit_job")
            self.assertEqual(Path(loaded.report.stdout_log).parent, Path(loaded.analysis.request_path).parent)
            self.assertFalse(loaded.report_ready)
            loaded.analysis.state = "completed"
            loaded.analysis.manifest_path = str(root / "manifest.json")
            loaded.report.plots_approved = True
            self.assertTrue(loaded.report_ready)

    def test_job_context_migrates_v1_to_v2_with_derived_manifest_defaults(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            config = root / "config.json"
            config.write_text("{}", encoding="utf-8")
            context = JobContext.create(
                project_root=root,
                bridge_id="unit",
                bridge_name="unit",
                data_root=root,
                start_date="2026-01-01",
                end_date="2026-01-01",
                config_path=config,
                selected_modules=["temperature"],
                options=options_for_modules(["temperature"]),
            )
            payload = context.to_dict()
            payload["schema_version"] = 1
            payload["report"].pop("derived_artifact_manifest_path", None)
            payload["report"].pop("derived_artifact_manifest_sha256", None)

            migrated = JobContext.from_dict(payload)

            self.assertEqual(migrated.schema_version, 3)
            self.assertEqual(migrated.report.derived_artifact_manifest_path, "")
            self.assertEqual(migrated.report.derived_artifact_manifest_sha256, "")

    def test_job_context_follows_opened_and_save_as_paths_without_serializing_binding(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            config = root / "config.json"
            config.write_text("{}", encoding="utf-8")
            context = JobContext.create(
                project_root=root,
                bridge_id="unit",
                bridge_name="unit",
                data_root=root / "data",
                start_date="2026-01-01",
                end_date="2026-01-01",
                config_path=config,
                selected_modules=["temperature"],
                options=options_for_modules(["temperature"]),
            )
            original = context.write()
            original_payload = json.loads(original.read_text(encoding="utf-8"))
            self.assertNotIn("_persistence_path", original_payload)

            opened_copy = root / "opened_elsewhere" / "renamed_context.json"
            opened_copy.parent.mkdir()
            opened_copy.write_text(
                json.dumps(original_payload, ensure_ascii=False), encoding="utf-8"
            )
            loaded = JobContext.read(opened_copy)
            loaded.analysis.state = "completed"
            self.assertEqual(loaded.write(), opened_copy.resolve())
            self.assertEqual(
                json.loads(opened_copy.read_text(encoding="utf-8"))["analysis"]["state"],
                "completed",
            )
            self.assertEqual(
                json.loads(original.read_text(encoding="utf-8"))["analysis"]["state"],
                "draft",
            )

            saved_as = root / "saved_as" / "job.json"
            loaded.analysis.state = "stopped"
            self.assertEqual(loaded.write(saved_as), saved_as.resolve())
            loaded.analysis.state = "failed"
            self.assertEqual(loaded.write(), saved_as.resolve())
            saved_payload = json.loads(saved_as.read_text(encoding="utf-8"))
            self.assertEqual(saved_payload["analysis"]["state"], "failed")
            self.assertNotIn("_persistence_path", saved_payload)
            self.assertEqual(
                json.loads(opened_copy.read_text(encoding="utf-8"))["analysis"]["state"],
                "completed",
            )

    def test_job_context_rejects_reversed_date_range(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            config = root / "config.json"
            config.write_text("{}", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "end_date"):
                JobContext.create(
                    project_root=root,
                    bridge_id="unit",
                    bridge_name="unit",
                    data_root=root,
                    start_date="2026-02-01",
                    end_date="2026-01-31",
                    config_path=config,
                    selected_modules=["temperature"],
                    options=options_for_modules(["temperature"]),
                )


if __name__ == "__main__":
    unittest.main()
