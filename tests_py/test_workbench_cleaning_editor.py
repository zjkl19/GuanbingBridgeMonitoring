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
    ExcludeRangeRow,
    apply_cleaning_thresholds,
    apply_exclude_ranges,
    apply_post_filter_thresholds,
    extract_cleaning_thresholds,
    extract_exclude_ranges,
    extract_post_filter_thresholds,
    PostFilterConfigEditorSession,
)

try:
    from PySide6.QtWidgets import QApplication

    from workbench.config_tab import CleaningThresholdEditorWidget, PostFilterThresholdEditorWidget
except ImportError:  # pragma: no cover - dependency gate
    QApplication = None
    CleaningThresholdEditorWidget = None
    PostFilterThresholdEditorWidget = None


FIXTURE = (
    Path(__file__).resolve().parents[1]
    / "tests"
    / "fixtures"
    / "workbench_cleaning_threshold_contract.json"
)


class WorkbenchCleaningEditorTests(unittest.TestCase):
    def setUp(self) -> None:
        self.payload = json.loads(FIXTURE.read_text(encoding="utf-8"))

    def test_extract_supports_one_sided_rules_and_explicit_exclusion(self) -> None:
        rows = extract_cleaning_thresholds(self.payload)
        temperature = next(row for row in rows if row.module_key == "temperature")
        point_rule = next(row for row in rows if row.point_key == "PT_1")
        self.assertIsNone(temperature.minimum)
        self.assertEqual(temperature.maximum, 50)
        self.assertEqual((point_rule.minimum, point_rule.maximum), (-10, 10))
        self.assertFalse(point_rule.zero_to_nan)
        exclusions = extract_exclude_ranges(self.payload)
        self.assertEqual(len(exclusions), 1)
        self.assertEqual(exclusions[0].point_key, "PT_1")
        self.assertEqual(exclusions[0].reason, "测试夹具中的明确整段排除规则")

    def test_inverted_numeric_threshold_is_rejected(self) -> None:
        with self.assertRaisesRegex(ConfigEditorError, "整段排除规则"):
            CleaningThresholdRow(
                "per_point", "deflection", "PT_1", 1000, -1000
            ).validated()

    def test_noop_round_trip_preserves_mixed_json_representations(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "config.json"
            path.write_text(json.dumps(self.payload, ensure_ascii=False, indent=2), encoding="utf-8")
            session = CleaningConfigEditorSession(path)
            self.assertEqual(session.build_payload(session.rows), self.payload)
            self.assertEqual(
                session.build_payload_all(session.rows, session.exclude_rows), self.payload
            )
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

    def test_canonical_exclude_ranges_round_trip_with_reason(self) -> None:
        payload = copy.deepcopy(self.payload)
        payload["per_point"]["deflection"]["PT_1"]["exclude_ranges"] = [
            {
                "start_time": "2025-12-15 00:00:00",
                "end_time": "2025-12-31 23:59:59",
                "reason": "该时段数据整体无效",
            }
        ]
        rows = extract_exclude_ranges(payload)
        self.assertEqual(
            rows,
            [
                ExcludeRangeRow(
                    "per_point",
                    "deflection",
                    "PT_1",
                    "2025-12-15 00:00:00",
                    "2025-12-31 23:59:59",
                    "该时段数据整体无效",
                )
            ],
        )
        self.assertEqual(apply_exclude_ranges(payload, rows), payload)
        with self.assertRaisesRegex(ConfigEditorError, "结束时间"):
            ExcludeRangeRow(
                "per_point",
                "deflection",
                "PT_1",
                "2025-12-31 00:00:00",
                "2025-12-15 00:00:00",
            ).validated()

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

    def test_post_filter_round_trip_and_edit_preserve_other_fields(self) -> None:
        rows = extract_post_filter_thresholds(self.payload)
        self.assertEqual(len(rows), 2)
        point = next(row for row in rows if row.point_key == "PT_1")
        self.assertIsNone(point.minimum)
        self.assertEqual(point.maximum, 4)
        self.assertEqual(point.t_range_start, "2026-01-01 00:00:00")
        updated = apply_post_filter_thresholds(
            self.payload,
            [
                CleaningThresholdRow(
                    row.scope,
                    row.module_key,
                    row.point_key,
                    row.minimum,
                    3 if row.point_key == "PT_1" else row.maximum,
                    row.t_range_start,
                    row.t_range_end,
                )
                for row in rows
            ],
        )
        self.assertEqual(
            updated["per_point"]["deflection"]["PT_1"]["post_filter_thresholds"][0]["max"],
            3,
        )
        self.assertEqual(updated["per_point"]["deflection"]["PT_1"]["offset_correction"], 12)
        self.assertEqual(
            updated["per_point"]["deflection"]["PT_1"]["thresholds"],
            self.payload["per_point"]["deflection"]["PT_1"]["thresholds"],
        )

    def test_all_bridge_post_filter_configs_noop_round_trip(self) -> None:
        root = Path(__file__).resolve().parents[1]
        profiles = json.loads(
            (root / "config" / "bridge_profiles.json").read_text(encoding="utf-8-sig")
        )["profiles"]
        for profile in profiles:
            with self.subTest(profile=profile["bridge_id"]):
                session = PostFilterConfigEditorSession(root / profile["default_config"])
                self.assertEqual(session.build_payload(session.rows), session.payload)


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
            self.assertEqual(widget.cleaning_tabs.count(), 2)
            self.assertEqual(widget.exclude_table.rowCount(), 1)
            self.assertEqual(widget.exclude_table.item(0, 2).text(), "PT_1")
            self.assertIn("明确整段排除", widget.exclude_table.item(0, 5).text())
        finally:
            widget.close()

    def test_cleaning_bounds_are_rounded_to_three_decimal_places(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "config.json"
            path.write_text(
                json.dumps(
                    {
                        "defaults": {
                            "deflection": {
                                "thresholds": {
                                    "min": -4.875565610859724,
                                    "max": 24.85294117647058,
                                }
                            }
                        }
                    }
                ),
                encoding="utf-8",
            )
            widget = CleaningThresholdEditorWidget()
            try:
                widget.load_path(path)
                self.assertEqual(widget.table.item(0, 3).text(), "-4.876")
                self.assertEqual(widget.table.item(0, 4).text(), "24.853")
                row = widget.rows()[0]
                self.assertEqual(
                    (row.minimum, row.maximum),
                    (-4.875565610859724, 24.85294117647058),
                )
                self.assertEqual(
                    widget.session.build_payload(widget.rows()), widget.session.payload
                )

                widget.table.item(0, 3).setText("-4.8764")
                edited = widget.rows()[0]
                self.assertEqual(
                    (edited.minimum, edited.maximum), (-4.876, 24.85294117647058)
                )
                updated = widget.session.build_payload([edited])
                self.assertEqual(
                    updated["defaults"]["deflection"]["thresholds"],
                    {"min": -4.876, "max": 24.85294117647058},
                )
            finally:
                widget.close()

    def test_post_filter_widget_hides_unsupported_columns(self) -> None:
        widget = PostFilterThresholdEditorWidget()
        try:
            widget.load_path(FIXTURE)
            self.assertEqual(widget.table.rowCount(), 2)
            self.assertTrue(widget.table.isColumnHidden(7))
            self.assertEqual(widget.rows(), widget.session.rows)
            self.assertEqual(widget.cleaning_tabs.count(), 1)
        finally:
            widget.close()


if __name__ == "__main__":
    unittest.main()
