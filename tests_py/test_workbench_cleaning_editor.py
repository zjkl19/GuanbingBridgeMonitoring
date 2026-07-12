from __future__ import annotations

import copy
import json
import os
import tempfile
import unittest
from pathlib import Path

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

from workbench.config_editor import (
    CleaningConfigEditorSession,
    CleaningThresholdRow,
    ConfigChangedError,
    ConfigEditorError,
    apply_cleaning_thresholds,
    extract_cleaning_thresholds,
)

try:
    from PySide6.QtWidgets import QApplication

    from workbench.config_tab import CleaningThresholdEditorWidget
except ImportError:  # pragma: no cover - dependency gate
    QApplication = None
    CleaningThresholdEditorWidget = None


FIXTURE = (
    Path(__file__).resolve().parents[1]
    / "tests"
    / "fixtures"
    / "workbench_cleaning_threshold_contract.json"
)


class WorkbenchCleaningEditorTests(unittest.TestCase):
    def setUp(self) -> None:
        self.payload = json.loads(FIXTURE.read_text(encoding="utf-8"))

    def test_extract_supports_one_sided_and_suppression_rules(self) -> None:
        rows = extract_cleaning_thresholds(self.payload)
        temperature = next(row for row in rows if row.module_key == "temperature")
        suppression = next(row for row in rows if row.point_key == "PT_1")
        self.assertIsNone(temperature.minimum)
        self.assertEqual(temperature.maximum, 50)
        self.assertEqual((suppression.minimum, suppression.maximum), (1000, -1000))
        self.assertFalse(suppression.zero_to_nan)

    def test_noop_round_trip_preserves_mixed_json_representations(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "config.json"
            path.write_text(json.dumps(self.payload, ensure_ascii=False, indent=2), encoding="utf-8")
            session = CleaningConfigEditorSession(path)
            self.assertEqual(session.build_payload(session.rows), self.payload)
            result = session.save(session.rows)
            self.assertFalse(result.changed)
            self.assertIsNone(result.backup_path)

    def test_apply_changes_only_managed_cleaning_fields(self) -> None:
        rows = extract_cleaning_thresholds(self.payload)
        edited = [
            CleaningThresholdRow(
                row.scope,
                row.module_key,
                row.point_key,
                -4 if row.scope == "defaults" and row.module_key == "deflection" else row.minimum,
                row.maximum,
                row.t_range_start,
                row.t_range_end,
                row.zero_to_nan,
                row.outlier_window_sec,
                row.outlier_threshold_factor,
            )
            for row in rows
        ]
        updated = apply_cleaning_thresholds(self.payload, edited)
        self.assertEqual(updated["plot_common"], self.payload["plot_common"])
        self.assertEqual(
            updated["per_point"]["deflection"]["PT_1"]["offset_correction"], 12
        )
        self.assertEqual(
            updated["per_point"]["deflection"]["PT_1"]["alarm_bounds"],
            self.payload["per_point"]["deflection"]["PT_1"]["alarm_bounds"],
        )
        self.assertEqual(updated["defaults"]["deflection"]["thresholds"][0]["min"], -4)

    def test_validation_rejects_partial_dates_and_conflicting_block_metadata(self) -> None:
        with self.assertRaisesRegex(ConfigEditorError, "同时填写"):
            CleaningThresholdRow(
                "defaults", "strain", "", -1, 1, "2026-01-01 00:00:00", ""
            ).validated()
        rows = [
            CleaningThresholdRow("defaults", "strain", "", -1, 1, zero_to_nan=True),
            CleaningThresholdRow("defaults", "strain", "", -2, 2, zero_to_nan=False),
        ]
        with self.assertRaisesRegex(ConfigEditorError, "zero_to_nan 不一致"):
            apply_cleaning_thresholds(copy.deepcopy(self.payload), rows)

    def test_save_backs_up_and_refuses_source_drift(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "config.json"
            path.write_text(json.dumps(self.payload), encoding="utf-8")
            session = CleaningConfigEditorSession(path)
            rows = session.rows
            changed = [
                CleaningThresholdRow(
                    row.scope,
                    row.module_key,
                    row.point_key,
                    row.minimum,
                    49 if row.module_key == "temperature" else row.maximum,
                    row.t_range_start,
                    row.t_range_end,
                    row.zero_to_nan,
                    row.outlier_window_sec,
                    row.outlier_threshold_factor,
                )
                for row in rows
            ]
            result = session.save(changed)
            self.assertTrue(result.changed)
            self.assertTrue(result.backup_path.is_file())

            stale = CleaningConfigEditorSession(path)
            path.write_text("{}", encoding="utf-8")
            with self.assertRaises(ConfigChangedError):
                stale.save(stale.rows)


@unittest.skipIf(QApplication is None, "PySide6 is not installed")
class WorkbenchCleaningEditorGuiTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.app = QApplication.instance() or QApplication([])

    def test_widget_loads_contract_rows_and_validates_table(self) -> None:
        widget = CleaningThresholdEditorWidget()
        try:
            widget.load_path(FIXTURE)
            self.assertEqual(widget.table.rowCount(), 3)
            self.assertEqual(widget.rows(), widget.session.rows)
            self.assertIn("3 条", widget.count_label.text())
        finally:
            widget.close()


if __name__ == "__main__":
    unittest.main()
