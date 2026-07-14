from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from workbench.analysis import AnalysisRequestBuilder
from workbench.config_layers import config_dependency_sha256, load_layered_config
from workbench.models import JobContext, file_sha256
from workbench.modules import options_for_modules


class WorkbenchConfigLayerTests(unittest.TestCase):
    def test_shared_fixture_fingerprint_matches_matlab_contract(self) -> None:
        fixture = Path(__file__).resolve().parents[1] / "tests" / "config" / "fingerprint" / "project.json"
        self.assertEqual(
            config_dependency_sha256(fixture),
            "01A68C332F2E2ACD36D3DCBE6C179C1D616BBCC841B89E28499D405EA99B17A6",
        )

    def test_unicode_fixture_fingerprint_matches_matlab_contract(self) -> None:
        fixture = Path(__file__).resolve().parents[1] / "tests" / "config" / "fingerprint" / "unicode_project.json"
        self.assertEqual(
            config_dependency_sha256(fixture),
            "CFE34E9BFA1BBD3359A621450AB61EB557E5081FECFFC44A58CBFFAE96CA90C5",
        )

    def test_cross_volume_dependency_fails_with_portable_message(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / "layer.json").write_text('{"value":1}', encoding="utf-8")
            entry = root / "project.json"
            entry.write_text('{"layers":["layer.json"]}', encoding="utf-8")
            with patch("workbench.config_layers.os.path.relpath", side_effect=ValueError("drive")):
                with self.assertRaisesRegex(ValueError, "same filesystem volume"):
                    config_dependency_sha256(entry)

    def test_monolithic_config_keeps_file_hash_compatibility(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "config.json"
            path.write_text('{"bridge":{"id":"unit"}}', encoding="utf-8")

            self.assertEqual(config_dependency_sha256(path), file_sha256(path))

    def test_layered_config_merges_dependencies_and_tracks_all_files(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / "base.json").write_text(
                json.dumps({"defaults": {"gap": 1}, "plot": {"ylabel": "old"}}),
                encoding="utf-8",
            )
            (root / "points.json").write_text(
                json.dumps({"P1": {"alarm_bounds": {"level1": [-1, 1]}}}),
                encoding="utf-8",
            )
            entry = root / "project.json"
            entry.write_text(
                json.dumps({
                    "extends": "base.json",
                    "includes": {"per_point": "points.json"},
                    "plot": {"title": "new"},
                }),
                encoding="utf-8",
            )

            config, dependencies = load_layered_config(entry)

            self.assertEqual(config["defaults"]["gap"], 1)
            self.assertEqual(config["plot"], {"ylabel": "old", "title": "new"})
            self.assertIn("P1", config["per_point"])
            self.assertEqual({path.name for path in dependencies}, {
                "base.json", "points.json", "project.json"
            })
            self.assertNotIn("extends", config)
            self.assertNotIn("includes", config)

    def test_dependency_hash_changes_when_included_file_changes(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            include = root / "points.json"
            include.write_text('{"P1":{"limit":1}}', encoding="utf-8")
            entry = root / "project.json"
            entry.write_text(
                '{"includes":{"per_point":"points.json"}}', encoding="utf-8"
            )
            entry_hash = file_sha256(entry)
            first = config_dependency_sha256(entry)

            include.write_text('{"P1":{"limit":2}}', encoding="utf-8")

            self.assertEqual(file_sha256(entry), entry_hash)
            self.assertNotEqual(config_dependency_sha256(entry), first)

    def test_dependency_hash_keeps_file_identity_when_layer_contents_are_swapped(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            first_layer = root / "a.json"
            second_layer = root / "b.json"
            first_layer.write_text('{"value":1}', encoding="utf-8")
            second_layer.write_text('{"value":2}', encoding="utf-8")
            entry = root / "project.json"
            entry.write_text('{"layers":["a.json","b.json"]}', encoding="utf-8")
            before_config, _ = load_layered_config(entry)
            before_hash = config_dependency_sha256(entry)

            first_layer.write_text('{"value":2}', encoding="utf-8")
            second_layer.write_text('{"value":1}', encoding="utf-8")
            after_config, _ = load_layered_config(entry)

            self.assertEqual(before_config["value"], 2)
            self.assertEqual(after_config["value"], 1)
            self.assertNotEqual(config_dependency_sha256(entry), before_hash)

    def test_analysis_request_embeds_merged_config_and_rejects_changed_dependency(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            data_root = root / "data"
            data_root.mkdir()
            base = root / "base.json"
            base.write_text('{"plot_common":{"gap_mode":"connect"}}', encoding="utf-8")
            entry = root / "project.json"
            entry.write_text('{"extends":"base.json","bridge":{"id":"unit"}}', encoding="utf-8")
            context = JobContext.create(
                project_root=root,
                bridge_id="unit",
                bridge_name="unit",
                data_root=data_root,
                start_date="2026-01-01",
                end_date="2026-01-02",
                config_path=entry,
                selected_modules=["temperature"],
                options=options_for_modules(["temperature"]),
                job_id="layered_unit",
            )

            payload = AnalysisRequestBuilder().build(context)
            self.assertEqual(payload["config"]["plot_common"]["gap_mode"], "connect")
            self.assertNotIn("extends", payload["config"])

            base.write_text('{"plot_common":{"gap_mode":"break"}}', encoding="utf-8")
            with self.assertRaisesRegex(RuntimeError, "Config changed"):
                AnalysisRequestBuilder().build(context)


if __name__ == "__main__":
    unittest.main()
