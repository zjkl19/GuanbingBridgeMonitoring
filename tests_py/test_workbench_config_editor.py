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
)


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


if __name__ == "__main__":
    unittest.main()
