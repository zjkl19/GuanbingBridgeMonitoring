from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from workbench.config_editor import (
    AlarmBoundRow,
    ConfigChangedError,
    ConfigEditorError,
    ConfigEditorSession,
    apply_alarm_bounds,
    extract_alarm_bounds,
    extract_effective_warning_rows,
    update_effective_warning_value,
)
from workbench.config_layers import config_dependency_sha256


def sample_config() -> dict:
    return {
        "meta": {"keep": "unchanged"},
        "defaults": {
            "wind": {"unit": "m/s", "alarm_bounds": {"level2": [-20, 20], "level1": [-10, 10]}},
        },
        "per_point": {
            "wind": {
                "W1": {"gain": 2, "alarm_bounds": {"level1": [0, 25]}},
                "W2": {"gain": 3},
            }
        },
    }


class WorkbenchConfigEditorTests(unittest.TestCase):
    @staticmethod
    def _write_layered_config(root: Path) -> tuple[Path, Path, Path]:
        base = root / "base.json"
        points = root / "points.json"
        entry = root / "entry.json"
        base.write_text(
            json.dumps(
                {
                    "meta": {"base": True},
                    "defaults": {
                        "wind": {
                            "unit": "m/s",
                            "alarm_bounds": {"level1": [-10, 10]},
                        }
                    },
                }
            ),
            encoding="utf-8",
        )
        points.write_text(
            json.dumps(
                {
                    "wind": {
                        "W2": {
                            "gain": 3,
                            "alarm_bounds": {"level1": [0, 30]},
                        }
                    }
                }
            ),
            encoding="utf-8",
        )
        entry.write_text(
            json.dumps(
                {
                    "extends": "base.json",
                    "includes": {"per_point": "points.json"},
                    "meta": {"entry": True},
                },
                separators=(",", ":"),
            ),
            encoding="utf-8",
        )
        return entry, base, points

    def test_extracts_defaults_and_per_point_in_level_order(self) -> None:
        rows = extract_alarm_bounds(sample_config())
        self.assertEqual([(row.scope, row.point_key, row.level) for row in rows], [
            ("defaults", "", "level1"),
            ("defaults", "", "level2"),
            ("per_point", "W1", "level1"),
        ])

    def test_apply_preserves_unrelated_fields_and_replaces_only_alarm_bounds(self) -> None:
        updated = apply_alarm_bounds(sample_config(), [
            AlarmBoundRow("defaults", "wind", "", "level1", -12, 12),
            AlarmBoundRow("per_point", "wind", "W2", "level1", 0, 30),
        ])
        self.assertEqual(updated["meta"], {"keep": "unchanged"})
        self.assertEqual(updated["defaults"]["wind"]["unit"], "m/s")
        self.assertEqual(updated["per_point"]["wind"]["W1"], {"gain": 2})
        self.assertEqual(updated["per_point"]["wind"]["W2"]["gain"], 3)
        self.assertEqual(updated["defaults"]["wind"]["alarm_bounds"]["level1"], [-12.0, 12.0])
        self.assertEqual(updated["per_point"]["wind"]["W2"]["alarm_bounds"]["level1"], [0.0, 30.0])

    def test_effective_warning_editor_preserves_each_source_semantics(self) -> None:
        payload = {
            "per_point": {
                "cable_accel": {
                    "CS1": {
                        "force_alarm_bounds": {"level2": [100, 200]},
                        "sensor": "keep",
                    }
                }
            },
            "wind_params": {"alarm_levels": [25, 30, 37.4]},
            "plot_styles": {
                "deflection": {
                    "warn_lines": [
                        {"y": -20, "label": "二级下限", "color": "red"}
                    ]
                }
            },
        }
        rows = extract_effective_warning_rows(payload)
        force = next(row for row in rows if row.source_kind == "force_alarm_bounds")
        level = next(row for row in rows if row.config_path == "wind_params.alarm_levels[1]")
        line = next(row for row in rows if row.source_kind == "warn_lines")
        updated = update_effective_warning_value(payload, force, "90, 210")
        updated = update_effective_warning_value(updated, level, "31")
        updated = update_effective_warning_value(updated, line, "-22")
        self.assertEqual(
            updated["per_point"]["cable_accel"]["CS1"]["force_alarm_bounds"]["level2"],
            [90, 210],
        )
        self.assertEqual(updated["per_point"]["cable_accel"]["CS1"]["sensor"], "keep")
        self.assertEqual(updated["wind_params"]["alarm_levels"], [25, 31, 37.4])
        self.assertEqual(updated["plot_styles"]["deflection"]["warn_lines"][0]["y"], -22)
        self.assertEqual(
            updated["plot_styles"]["deflection"]["warn_lines"][0]["label"],
            "二级下限",
        )

    def test_effective_warning_editor_rejects_invalid_level_order(self) -> None:
        payload = {"wind_params": {"alarm_levels": [25, 30, 37.4]}}
        row = next(
            item
            for item in extract_effective_warning_rows(payload)
            if item.config_path == "wind_params.alarm_levels[1]"
        )
        with self.assertRaisesRegex(Exception, "等级顺序"):
            update_effective_warning_value(payload, row, "40")

    def test_rejects_invalid_bounds_and_duplicates(self) -> None:
        with self.assertRaises(ConfigEditorError):
            apply_alarm_bounds(sample_config(), [AlarmBoundRow("per_point", "wind", "W1", "二级", 0, 20)])
        with self.assertRaises(ConfigEditorError):
            apply_alarm_bounds(sample_config(), [AlarmBoundRow("per_point", "wind", "W1", "level1", 20, 20)])
        duplicate = AlarmBoundRow("per_point", "wind", "W1", "level1", 0, 20)
        with self.assertRaises(ConfigEditorError):
            apply_alarm_bounds(sample_config(), [duplicate, duplicate])

    def test_save_creates_backup_and_round_trips(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "config.json"
            path.write_text(json.dumps(sample_config(), ensure_ascii=False), encoding="utf-8")
            session = ConfigEditorSession(path)
            result = session.save([AlarmBoundRow("per_point", "wind", "W1", "level2", 0, 35)])
            self.assertTrue(result.changed)
            self.assertIsNotNone(result.backup_path)
            self.assertTrue(result.backup_path.is_file())
            self.assertEqual(ConfigEditorSession(path).rows[0].level, "level2")

    def test_unchanged_save_does_not_reformat_or_create_backup(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "config.json"
            original = json.dumps(sample_config(), ensure_ascii=False, separators=(",", ":"))
            path.write_text(original, encoding="utf-8")
            session = ConfigEditorSession(path)
            result = session.save(session.rows)
            self.assertFalse(result.changed)
            self.assertIsNone(result.backup_path)
            self.assertEqual(path.read_text(encoding="utf-8"), original)

    def test_save_refuses_external_source_change(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "config.json"
            path.write_text(json.dumps(sample_config()), encoding="utf-8")
            session = ConfigEditorSession(path)
            payload = sample_config()
            payload["external"] = True
            path.write_text(json.dumps(payload), encoding="utf-8")
            with self.assertRaises(ConfigChangedError):
                session.save(session.rows)

    def test_layered_session_exposes_effective_config_and_dependency_fingerprint(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            entry, base, points = self._write_layered_config(Path(folder))
            session = ConfigEditorSession(entry)

            self.assertTrue(session.is_layered)
            self.assertEqual(session.loaded_sha256, config_dependency_sha256(entry))
            self.assertEqual(set(session.dependencies), {entry, base, points})
            self.assertEqual(session.payload["meta"], {"base": True, "entry": True})
            self.assertEqual(session.payload["defaults"]["wind"]["unit"], "m/s")
            self.assertEqual(session.payload["per_point"]["wind"]["W2"]["gain"], 3)
            self.assertNotIn("extends", session.payload)
            self.assertNotIn("includes", session.payload)

    def test_layered_noop_does_not_rewrite_entry(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            entry, _, _ = self._write_layered_config(Path(folder))
            original = entry.read_bytes()
            session = ConfigEditorSession(entry)

            result = session.save_payload(session.payload)

            self.assertFalse(result.changed)
            self.assertEqual(result.sha256, session.loaded_sha256)
            self.assertEqual(entry.read_bytes(), original)

    def test_layered_changed_source_requires_flattened_save_copy(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            entry, _, _ = self._write_layered_config(root)
            original = entry.read_bytes()
            session = ConfigEditorSession(entry)
            updated = session.build_payload(
                [AlarmBoundRow("defaults", "wind", "", "level1", -12, 12)]
            )

            with self.assertRaisesRegex(ConfigEditorError, "分层组合"):
                session.save_payload(updated)

            self.assertEqual(entry.read_bytes(), original)
            self.assertEqual(list(root.glob("entry_backup_workbench_*.json")), [])

    def test_layered_save_copy_writes_flattened_effective_config(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            entry, _, _ = self._write_layered_config(root)
            original = entry.read_bytes()
            target = root / "flattened.json"
            session = ConfigEditorSession(entry)
            updated = session.build_payload(
                [AlarmBoundRow("defaults", "wind", "", "level1", -12, 12)]
            )

            result = session.save_payload(updated, target=target)

            self.assertTrue(result.changed)
            self.assertEqual(entry.read_bytes(), original)
            flattened = json.loads(target.read_text(encoding="utf-8"))
            self.assertEqual(flattened, updated)
            self.assertNotIn("extends", flattened)
            self.assertNotIn("includes", flattened)
            self.assertFalse(ConfigEditorSession(target).is_layered)

    def test_layered_dependency_drift_blocks_save_copy(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            entry, base, _ = self._write_layered_config(root)
            session = ConfigEditorSession(entry)
            base_payload = json.loads(base.read_text(encoding="utf-8"))
            base_payload["external"] = True
            base.write_text(json.dumps(base_payload), encoding="utf-8")

            with self.assertRaises(ConfigChangedError):
                session.save_payload(session.payload, target=root / "flattened.json")

    def test_layered_save_copy_cannot_overwrite_a_dependency(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            entry, base, _ = self._write_layered_config(Path(folder))
            original_base = base.read_bytes()
            session = ConfigEditorSession(entry)

            with self.assertRaisesRegex(ConfigEditorError, "依赖文件"):
                session.save_payload(session.payload, target=base)

            self.assertEqual(base.read_bytes(), original_base)


if __name__ == "__main__":
    unittest.main()
