from __future__ import annotations

import os
import tempfile
import unittest
from pathlib import Path

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

from workbench.auto_threshold import PreviewSeries
from workbench.config_editor import CleaningThresholdRow, ConfigEditorError
from workbench.manual_threshold import (
    LOWER_SIDE,
    UPPER_SIDE,
    OneSidedThresholdDraft,
    accepted_point_ids,
    estimate_one_sided_rule,
    merge_one_sided_rule,
    select_preview_series,
)

try:
    from PySide6.QtCore import QDateTime, QPoint, Qt
    from PySide6.QtTest import QTest
    from PySide6.QtWidgets import QApplication, QDialog

    from workbench.config_tab import CleaningThresholdEditorWidget
    from workbench.manual_threshold_dialog import (
        OneSidedThresholdCurveView,
        OneSidedThresholdDialog,
    )
except ImportError:  # pragma: no cover
    QApplication = None


FIXTURE = (
    Path(__file__).resolve().parents[1]
    / "tests"
    / "fixtures"
    / "workbench_cleaning_threshold_contract.json"
)


class ManualThresholdServiceTests(unittest.TestCase):
    def setUp(self) -> None:
        self.series = PreviewSeries(
            "deflection",
            "PT-1",
            "deflection",
            (
                "2026-01-01 00:00:00",
                "2026-01-01 01:00:00",
                "2026-01-01 02:00:00",
                "2026-01-01 03:00:00",
            ),
            (0.0, 5.0, 10.0, 15.0),
        )

    def test_preview_identity_is_exact_and_unique(self) -> None:
        previews = {self.series.key: self.series}
        selected = select_preview_series(
            previews, module_key="deflection", point_ids=("PT_1", "PT-1")
        )
        self.assertIs(selected, self.series)
        with self.assertRaisesRegex(ConfigEditorError, "身份不一致"):
            select_preview_series(
                previews, module_key="acceleration", point_ids=("PT-1",)
            )
        with self.assertRaisesRegex(ConfigEditorError, "多条"):
            select_preview_series(
                {
                    self.series.key: self.series,
                    ("deflection", "PT_1"): PreviewSeries(
                        "deflection", "PT_1", "deflection", self.series.times, self.series.values
                    ),
                },
                module_key="deflection",
                point_ids=("PT_1", "PT-1"),
            )

    def test_estimate_uses_strict_side_and_time_window(self) -> None:
        lower = OneSidedThresholdDraft(
            "deflection",
            "PT_1",
            LOWER_SIDE,
            8,
            "2026-01-01 01:00:00",
            "2026-01-01 02:00:00",
        )
        estimate = estimate_one_sided_rule(
            self.series, lower, accepted_preview_point_ids=("PT_1", "PT-1")
        )
        self.assertEqual(estimate.preview_sample_count, 4)
        self.assertEqual(estimate.finite_count, 4)
        self.assertEqual(estimate.applicable_count, 2)
        self.assertEqual(estimate.removed_count, 1)
        self.assertEqual(estimate.removed_ratio, 0.5)
        self.assertIn("完整缓存复算", estimate.summary_text())

        upper = OneSidedThresholdDraft("deflection", "PT_1", UPPER_SIDE, 10)
        estimate = estimate_one_sided_rule(
            self.series, upper, accepted_preview_point_ids=("PT-1",)
        )
        self.assertEqual(estimate.removed_count, 1)

    def test_merge_appends_replaces_and_rejects_duplicate(self) -> None:
        rows = [
            CleaningThresholdRow(
                "per_point", "deflection", "PT_1", -10, 10, zero_to_nan=False
            )
        ]
        draft = OneSidedThresholdDraft("deflection", "PT_1", LOWER_SIDE, -3)
        merged, index, replaced = merge_one_sided_rule(
            rows, selected_index=0, draft=draft
        )
        self.assertFalse(replaced)
        self.assertEqual(index, 1)
        self.assertEqual(len(merged), 2)
        self.assertEqual(merged[1].minimum, -3)
        self.assertIsNone(merged[1].maximum)
        self.assertFalse(merged[1].zero_to_nan)
        with self.assertRaisesRegex(ConfigEditorError, "已存在"):
            merge_one_sided_rule(merged, selected_index=0, draft=draft)

        replacement = OneSidedThresholdDraft("deflection", "PT_1", LOWER_SIDE, -2)
        replaced_rows, index, replaced = merge_one_sided_rule(
            merged, selected_index=1, draft=replacement
        )
        self.assertTrue(replaced)
        self.assertEqual(index, 1)
        self.assertEqual(replaced_rows[1].minimum, -2)

    def test_aliases_come_only_from_exact_name_map(self) -> None:
        payload = {"name_map_global": {"PT_1": "PT-1", "OTHER": "PT-10"}}
        self.assertEqual(accepted_point_ids(payload, "PT_1"), ("PT_1", "PT-1"))
        self.assertEqual(accepted_point_ids({}, "PT_1"), ("PT_1",))


@unittest.skipIf(QApplication is None, "PySide6 is not installed")
class ManualThresholdGuiTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.app = QApplication.instance() or QApplication([])

    @staticmethod
    def series() -> PreviewSeries:
        return PreviewSeries(
            "deflection",
            "PT_1",
            "deflection",
            tuple(f"2026-01-01 00:0{i}:00" for i in range(6)),
            (0.0, 2.0, 4.0, 6.0, 8.0, 10.0),
        )

    def test_curve_supports_mouse_drag(self) -> None:
        curve = OneSidedThresholdCurveView()
        curve.resize(700, 420)
        curve.set_rule(self.series(), side=LOWER_SIDE, threshold=5)
        values: list[float] = []
        curve.threshold_changed.connect(values.append)
        curve.show()
        self.app.processEvents()
        frame = curve._frame()
        start = QPoint(int(frame.center().x()), int(frame.bottom() - 5))
        end = QPoint(int(frame.center().x()), int(frame.top() + 5))
        QTest.mousePress(curve, Qt.LeftButton, Qt.NoModifier, start)
        QTest.mouseMove(curve, end, 5)
        QTest.mouseRelease(curve, Qt.LeftButton, Qt.NoModifier, end)
        self.app.processEvents()
        try:
            self.assertGreaterEqual(len(values), 2)
            self.assertGreater(values[-1], values[0])
        finally:
            curve.close()

    def test_dialog_shows_exact_value_window_and_preview_estimate(self) -> None:
        target = CleaningThresholdRow("per_point", "deflection", "PT_1", None, None)
        dialog = OneSidedThresholdDialog(
            target,
            side=LOWER_SIDE,
            accepted_preview_point_ids=("PT_1",),
            preview_series=self.series(),
        )
        try:
            dialog.threshold_edit.setText("4.125")
            dialog.time_window_check.setChecked(True)
            dialog.start_edit.setDateTime(
                QDateTime.fromString("2026-01-01 00:01:00", "yyyy-MM-dd HH:mm:ss")
            )
            dialog.end_edit.setDateTime(
                QDateTime.fromString("2026-01-01 00:04:00", "yyyy-MM-dd HH:mm:ss")
            )
            self.app.processEvents()
            draft = dialog.draft()
            self.assertEqual(draft.value, 4.125)
            self.assertEqual(draft.t_range_start, "2026-01-01 00:01:00")
            self.assertEqual(draft.t_range_end, "2026-01-01 00:04:00")
            self.assertIn("预计删除 2 个", dialog.estimate_label.text())
            self.assertIn("完整缓存复算", dialog.estimate_label.text())
        finally:
            dialog.close()

    def test_dialog_normalizes_mixed_timezone_preview_times(self) -> None:
        series = PreviewSeries(
            "deflection",
            "PT_1",
            "deflection",
            (
                "2026-01-01T00:00:00Z",
                "2026-01-01 08:01:00",
            ),
            (1.0, 2.0),
        )
        target = CleaningThresholdRow("per_point", "deflection", "PT_1", None, None)
        dialog = OneSidedThresholdDialog(
            target,
            side=LOWER_SIDE,
            accepted_preview_point_ids=("PT_1",),
            preview_series=series,
        )
        try:
            self.assertLessEqual(dialog.start_edit.dateTime(), dialog.end_edit.dateTime())
        finally:
            dialog.close()

    def test_cleaning_page_exposes_and_routes_curve_drag_entry(self) -> None:
        widget = CleaningThresholdEditorWidget()
        widget.load_path(FIXTURE)
        point_row = next(
            index
            for index in range(widget.table.rowCount())
            if widget.table.item(index, 2).text() == "PT_1"
        )
        routed_sides: list[str] = []
        opened_dialogs: list[OneSidedThresholdDialog] = []

        class RoutedDialog(OneSidedThresholdDialog):
            def __init__(
                self,
                target: CleaningThresholdRow,
                *,
                side: str,
                **kwargs: object,
            ) -> None:
                super().__init__(target, side=side, **kwargs)
                routed_sides.append(side)
                opened_dialogs.append(self)

            def exec(self) -> int:
                return QDialog.Rejected

        try:
            widget.resize(1500, 900)
            widget.show()
            widget.table.selectRow(point_row)
            widget.single_side_dialog_class = RoutedDialog
            self.app.processEvents()

            self.assertEqual(widget.manual_threshold_group.objectName(), "manualThresholdGroup")
            self.assertIn("曲线拖线入口", widget.manual_threshold_entry_label.text())
            self.assertIn("打开曲线预览并拖线设置下限", widget.lower_threshold_button.text())
            self.assertIn("删除低于阈值的数据", widget.lower_threshold_button.text())
            self.assertIn("打开曲线预览并拖线设置上限", widget.upper_threshold_button.text())
            self.assertIn("删除高于阈值的数据", widget.upper_threshold_button.text())
            self.assertEqual(
                widget.lower_threshold_button.objectName(), "openLowerThresholdCurveButton"
            )
            self.assertEqual(
                widget.upper_threshold_button.objectName(), "openUpperThresholdCurveButton"
            )

            QTest.mouseClick(widget.lower_threshold_button, Qt.LeftButton)
            QTest.mouseClick(widget.upper_threshold_button, Qt.LeftButton)
            self.app.processEvents()
            self.assertEqual(routed_sides, [LOWER_SIDE, UPPER_SIDE])
            self.assertEqual(len(opened_dialogs), 2)
            self.assertTrue(
                all(
                    isinstance(dialog.curve, OneSidedThresholdCurveView)
                    for dialog in opened_dialogs
                )
            )
            self.assertIn("打开曲线预览并拖线设置", widget.message_label.text())

            with tempfile.TemporaryDirectory() as temp_dir:
                screenshot = Path(temp_dir) / "manual_threshold_entry.png"
                pixmap = widget.grab()
                self.assertFalse(pixmap.isNull())
                self.assertTrue(pixmap.save(str(screenshot)))
                self.assertGreater(screenshot.stat().st_size, 10_000)
        finally:
            for dialog in opened_dialogs:
                dialog.close()
            widget.close()

    def test_cleaning_page_applies_cancel_and_undo(self) -> None:
        widget = CleaningThresholdEditorWidget()
        widget.load_path(FIXTURE)
        point_row = next(
            index
            for index in range(widget.table.rowCount())
            if widget.table.item(index, 2).text() == "PT_1"
        )

        class AcceptedDialog:
            def __init__(
                self,
                target: CleaningThresholdRow,
                *,
                side: str,
                **_kwargs: object,
            ) -> None:
                self._draft = OneSidedThresholdDraft(
                    target.module_key,
                    target.point_key,
                    side,
                    -2.5,
                    "2026-01-05 00:00:00",
                    "2026-01-06 00:00:00",
                )

            def exec(self) -> int:
                return QDialog.Accepted

            def draft(self) -> OneSidedThresholdDraft:
                return self._draft

            def estimate_summary(self) -> str:
                return "基于预览估计；正式值需使用完整缓存复算"

        class CancelledDialog(AcceptedDialog):
            def exec(self) -> int:
                return QDialog.Rejected

        try:
            widget.table.selectRow(point_row)
            before = widget.rows()
            widget.single_side_dialog_class = CancelledDialog
            widget.open_single_sided_threshold(LOWER_SIDE)
            self.assertEqual(widget.rows(), before)

            widget.single_side_dialog_class = AcceptedDialog
            widget.open_single_sided_threshold(LOWER_SIDE)
            self.assertEqual(widget.table.rowCount(), len(before) + 1)
            added = widget.rows()[-1]
            self.assertEqual(added.minimum, -2.5)
            self.assertIsNone(added.maximum)
            self.assertIn("尚未保存", widget.message_label.text())
            self.assertTrue(widget.undo_single_side_button.isEnabled())

            widget.undo_single_sided_threshold()
            self.assertEqual(widget.rows(), before)
            self.assertFalse(widget.undo_single_side_button.isEnabled())
        finally:
            widget.close()


if __name__ == "__main__":
    unittest.main()
