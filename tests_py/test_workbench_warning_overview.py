from __future__ import annotations

import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from workbench.__main__ import _parser
os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

from workbench.config_editor import ConfigEditorSession, extract_effective_warning_rows

try:
    from PySide6.QtCore import Qt
    from PySide6.QtWidgets import QApplication, QMessageBox

    from workbench.config_tab import AlarmBoundsEditorWidget
except ImportError:  # pragma: no cover - dependency gate
    QApplication = None
    AlarmBoundsEditorWidget = None


ROOT = Path(__file__).resolve().parents[1]
GUANBING_CONFIG = ROOT / "config" / "default_config.json"


class WorkbenchWarningOverviewTests(unittest.TestCase):
    def test_noconsole_invalid_cli_exits_cleanly_and_logs_diagnostic(self) -> None:
        with patch("workbench.__main__.sys.stderr", None), patch(
            "workbench.__main__._write_cli_diagnostic"
        ) as write_diagnostic:
            with self.assertRaises(SystemExit) as raised:
                _parser().parse_args(["--definitely-invalid-workbench-option"])
        self.assertEqual(raised.exception.code, 2)
        self.assertIn("unrecognized arguments", write_diagnostic.call_args.args[0])

    def test_invalid_cli_with_broken_redirect_exits_cleanly_and_logs_diagnostic(self) -> None:
        class BrokenRedirect:
            def write(self, _message: str) -> None:
                raise OSError(22, "Invalid argument")

        with patch("workbench.__main__.sys.stderr", BrokenRedirect()), patch(
            "workbench.__main__._write_cli_diagnostic"
        ) as write_diagnostic:
            with self.assertRaises(SystemExit) as raised:
                _parser().parse_args(["--definitely-invalid-workbench-option"])
        self.assertEqual(raised.exception.code, 2)
        self.assertTrue(write_diagnostic.called)
        self.assertIn(
            "unrecognized arguments",
            "\n".join(call.args[0] for call in write_diagnostic.call_args_list),
        )

    def test_mixed_warning_schemas_keep_distinct_semantics_and_provenance(self) -> None:
        payload = {
            "defaults": {
                "deflection": {"alarm_bounds": {"level2": [-10, 20]}},
            },
            "per_point": {
                "cable_accel": {
                    "CS1": {"force_alarm_bounds": {"level2": [100, 200], "level3": []}},
                },
                "wind": {"W1": {"alarm_levels": [25, 30, 37.4]}},
            },
            "plot_styles": {
                "deflection": {
                    "warn_lines": [{"y": -10, "label": "二级下限"}],
                    "rms_warn_lines": [10, 20],
                    "group_warn_lines": {"G1": [{"y": 20, "label": "二级上限"}]},
                }
            },
            "eq_params": {"alarm_levels": [1.0, 1.7]},
        }
        rows = extract_effective_warning_rows(payload)
        sources = {row.source_kind for row in rows}
        self.assertEqual(
            sources,
            {
                "alarm_bounds",
                "force_alarm_bounds",
                "alarm_levels",
                "warn_lines",
                "rms_warn_lines",
                "group_warn_lines",
            },
        )
        bound = next(row for row in rows if row.source_kind == "alarm_bounds")
        force = next(
            row
            for row in rows
            if row.source_kind == "force_alarm_bounds" and row.level == "level2"
        )
        group_line = next(row for row in rows if row.source_kind == "group_warn_lines")
        self.assertEqual((bound.value_text, bound.unit), ("[-10, 20]", "mm"))
        self.assertEqual((force.value_text, force.unit), ("[100, 200]", "kN"))
        self.assertEqual(group_line.target_key, "G1")
        self.assertIn("plot_styles.deflection.group_warn_lines.G1", group_line.config_path)
        self.assertEqual(
            [row.value_text for row in rows if row.source_kind == "rms_warn_lines"],
            ["10", "20"],
        )
        self.assertEqual(
            next(row for row in rows if row.config_path.endswith("force_alarm_bounds.level3")).status,
            "unset",
        )

    def test_invalid_levels_are_visible_instead_of_hiding_the_page(self) -> None:
        payload = {
            "wind_params": {"alarm_levels": [25, 20]},
            "plot_styles": {"tilt": {"warn_lines": [{"y": "not-a-number"}]}},
        }
        rows = extract_effective_warning_rows(payload)
        invalid_paths = {row.config_path for row in rows if row.status == "invalid"}
        self.assertIn("wind_params.alarm_levels[1]", invalid_paths)
        self.assertIn("plot_styles.tilt.warn_lines[0]", invalid_paths)

    def test_guanbing_exposes_real_values_when_alarm_bounds_are_absent(self) -> None:
        session = ConfigEditorSession(GUANBING_CONFIG)
        self.assertEqual(session.rows, [])
        rows = session.effective_warning_rows
        self.assertEqual(len(rows), 12)
        self.assertEqual(sum(row.status == "configured" for row in rows), 11)
        self.assertEqual(sum(row.status == "unset" for row in rows), 1)
        values = {(row.module_key, row.value_text, row.unit) for row in rows}
        self.assertIn(("wind", "≥ 25", "m/s"), values)
        self.assertIn(("deflection", "-21", "mm"), values)
        self.assertIn(("tilt", "0.155", "°"), values)

    def test_all_six_profiles_have_valid_overview_and_exact_noop_round_trip(self) -> None:
        profiles = json.loads(
            (ROOT / "config" / "bridge_profiles.json").read_text(encoding="utf-8-sig")
        )["profiles"]
        self.assertEqual(len(profiles), 6)
        for profile in profiles:
            with self.subTest(profile=profile["bridge_id"]):
                session = ConfigEditorSession(ROOT / profile["default_config"])
                rows = session.effective_warning_rows
                self.assertTrue(rows)
                self.assertFalse([row for row in rows if row.status == "invalid"])
                self.assertEqual(session.build_payload(session.rows), session.payload)


@unittest.skipIf(QApplication is None, "PySide6 is not installed")
class WorkbenchWarningOverviewGuiTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.app = QApplication.instance() or QApplication([])

    def test_guanbing_opens_on_nonempty_overview_and_keeps_explicit_editor(self) -> None:
        widget = AlarmBoundsEditorWidget()
        try:
            widget.load_path(GUANBING_CONFIG)
            self.assertEqual(widget.inner_tabs.count(), 2)
            self.assertEqual(widget.inner_tabs.currentIndex(), 0)
            self.assertEqual(widget.effective_table.rowCount(), 12)
            for column in range(widget.effective_table.columnCount()):
                self.assertTrue(
                    widget.effective_table.item(0, column).toolTip(),
                    f"column {column}",
                )
            self.assertEqual(widget.table.rowCount(), 0)
            self.assertIn("11 条有效", widget.overview_summary_label.text())
            self.assertIn("其它预警值和参考线", widget.overview_summary_label.text())
            self.assertFalse(widget.empty_bounds_label.isHidden())
            self.assertTrue(widget.table.isHidden())
            self.assertIn("不是加载失败", widget.empty_bounds_label.text())
            self.assertEqual(widget.inner_tabs.tabText(1), "双边上下限（未配置）")

            source_index = widget.source_filter.findData("alarm_levels")
            widget.source_filter.setCurrentIndex(source_index)
            self.assertEqual(widget.effective_table.rowCount(), 3)
            widget.warning_search.setText("29.92")
            self.assertEqual(widget.effective_table.rowCount(), 1)
            self.assertEqual(widget.effective_table.item(0, 5).text(), "≥ 29.92")
        finally:
            widget.close()

    def test_common_warning_sources_are_editable_and_saved_without_semantic_conversion(self) -> None:
        payload = {
            "per_point": {
                "cable_accel": {
                    "CS1": {"force_alarm_bounds": {"level2": [100, 200]}}
                }
            },
            "wind_params": {"alarm_levels": [25, 30, 37.4]},
            "plot_styles": {
                "deflection": {
                    "warn_lines": [{"y": -20, "label": "二级下限", "color": "red"}]
                }
            },
        }
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "config.json"
            path.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")
            widget = AlarmBoundsEditorWidget()
            try:
                widget.load_path(path)
                edits = {
                    "per_point.cable_accel.CS1.force_alarm_bounds.level2": "90, 210",
                    "wind_params.alarm_levels[1]": "31",
                    "plot_styles.deflection.warn_lines[0]": "-22",
                }
                for config_path, value in edits.items():
                    row_index = next(
                        index
                        for index in range(widget.effective_table.rowCount())
                        if widget.effective_table.item(index, 9).data(Qt.UserRole) == config_path
                    )
                    widget.effective_table.setCurrentCell(row_index, 0)
                    with patch("workbench.config_tab.QInputDialog.getText", return_value=(value, True)):
                        widget._edit_selected_effective_value()
                self.assertEqual(json.loads(path.read_text(encoding="utf-8")), payload)
                with patch(
                    "workbench.config_tab.QMessageBox.question",
                    return_value=QMessageBox.Yes,
                ), patch("workbench.config_tab.QMessageBox.information"):
                    widget._save_source()
                updated = json.loads(path.read_text(encoding="utf-8"))
                self.assertEqual(
                    updated["per_point"]["cable_accel"]["CS1"]["force_alarm_bounds"]["level2"],
                    [90, 210],
                )
                self.assertEqual(updated["wind_params"]["alarm_levels"], [25, 31, 37.4])
                self.assertEqual(updated["plot_styles"]["deflection"]["warn_lines"][0]["y"], -22)
                self.assertEqual(
                    updated["plot_styles"]["deflection"]["warn_lines"][0]["label"],
                    "二级下限",
                )
            finally:
                widget.close()


if __name__ == "__main__":
    unittest.main()
