from __future__ import annotations

import json
import os
import tempfile
import unittest
from datetime import datetime
from pathlib import Path

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

from workbench.auto_threshold import AutoThresholdError, PreviewSeries
from workbench.config_editor import CleaningThresholdRow, ConfigEditorError
from workbench.threshold_curve import ThresholdCurveError
from workbench.manual_threshold import (
    LOWER_SIDE,
    UPPER_SIDE,
    BoxThresholdProposal,
    OneSidedThresholdDraft,
    ThresholdSelectionBox,
    TwoSidedThresholdDraft,
    accepted_point_ids,
    apply_one_sided_to_selected_row,
    estimate_one_sided_rule,
    estimate_two_sided_rule,
    merge_one_sided_rule,
    merge_two_sided_rule,
    propose_box_threshold,
    select_preview_series,
)

try:
    from PySide6.QtCore import QDateTime, QPoint, QRectF, Qt
    from PySide6.QtTest import QTest
    from PySide6.QtWidgets import QApplication, QDialog, QLabel

    from workbench.config_tab import (
        CleaningThresholdEditorWidget,
        PostFilterThresholdEditorWidget,
    )
    from workbench.box_threshold_dialog import BoxThresholdCurveView, BoxThresholdDialog
    from workbench.manual_threshold_dialog import (
        OneSidedThresholdCurveView,
        OneSidedThresholdDialog,
        ThresholdBandCurveView,
        ThresholdBandDialog,
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

    def test_two_sided_estimate_is_strict_and_uses_one_shared_window(self) -> None:
        full = TwoSidedThresholdDraft("deflection", "PT_1", 5, 10)
        estimate = estimate_two_sided_rule(
            self.series, full, accepted_preview_point_ids=("PT_1", "PT-1")
        )
        self.assertEqual(estimate.applicable_count, 4)
        self.assertEqual(estimate.removed_count, 2)

        windowed = TwoSidedThresholdDraft(
            "deflection",
            "PT_1",
            5,
            10,
            "2026-01-01 01:00:00",
            "2026-01-01 02:00:00",
        )
        estimate = estimate_two_sided_rule(
            self.series, windowed, accepted_preview_point_ids=("PT-1",)
        )
        self.assertEqual(estimate.applicable_count, 2)
        self.assertEqual(estimate.removed_count, 0)
        with self.assertRaisesRegex(ConfigEditorError, "下限小于上限"):
            TwoSidedThresholdDraft("deflection", "PT_1", 10, 10).validated()

    def test_two_sided_merge_replaces_selected_rule_and_preserves_other_fields(self) -> None:
        rows = [
            CleaningThresholdRow(
                "per_point",
                "deflection",
                "PT_1",
                -10,
                10,
                zero_to_nan=False,
                outlier_window_sec=30,
                outlier_threshold_factor=3,
            )
        ]
        draft = TwoSidedThresholdDraft(
            "deflection",
            "PT_1",
            -2,
            12,
            "2026-01-01 01:00:00",
            "2026-01-01 02:00:00",
        )
        merged, index, replaced = merge_two_sided_rule(
            rows, selected_index=0, draft=draft
        )
        self.assertTrue(replaced)
        self.assertEqual(index, 0)
        self.assertEqual(len(merged), 1)
        self.assertEqual((merged[0].minimum, merged[0].maximum), (-2, 12))
        self.assertEqual(
            (merged[0].t_range_start, merged[0].t_range_end),
            ("2026-01-01 01:00:00", "2026-01-01 02:00:00"),
        )
        self.assertFalse(merged[0].zero_to_nan)
        self.assertEqual(merged[0].outlier_window_sec, 30)
        self.assertEqual(merged[0].outlier_threshold_factor, 3)
        with self.assertRaisesRegex(ConfigEditorError, "不一致"):
            merge_two_sided_rule(
                rows,
                selected_index=0,
                draft=TwoSidedThresholdDraft("acceleration", "PT_1", -2, 12),
            )

    def test_box_candidate_uses_actual_extreme_and_strict_estimate(self) -> None:
        lower_box = ThresholdSelectionBox(
            "deflection",
            "PT_1",
            LOWER_SIDE,
            "2026-01-01 00:00:00",
            "2026-01-01 02:00:00",
            4,
            11,
        )
        candidate = propose_box_threshold(
            self.series,
            lower_box,
            accepted_preview_point_ids=("PT_1", "PT-1"),
        )
        self.assertIsInstance(candidate, BoxThresholdProposal)
        self.assertEqual(candidate.selected_sample_count, 2)
        self.assertEqual(candidate.threshold, 10)
        self.assertEqual(candidate.estimate.removed_count, 2)

        upper_box = ThresholdSelectionBox(
            "deflection",
            "PT_1",
            UPPER_SIDE,
            "2026-01-01 00:00:00",
            "2026-01-01 02:00:00",
            4,
            11,
            "2026-01-01 01:00:00",
            "2026-01-01 02:00:00",
        )
        candidate = propose_box_threshold(
            self.series,
            upper_box,
            accepted_preview_point_ids=("PT-1",),
        )
        self.assertEqual(candidate.selected_sample_count, 2)
        self.assertEqual(candidate.threshold, 5)
        self.assertEqual(candidate.estimate.applicable_count, 2)
        self.assertEqual(candidate.estimate.removed_count, 1)

    def test_box_candidate_rejects_zero_hit_nonfinite_and_identity_mismatch(self) -> None:
        empty_box = ThresholdSelectionBox(
            "deflection",
            "PT_1",
            LOWER_SIDE,
            "2026-01-01 00:00:00",
            "2026-01-01 03:00:00",
            20,
            30,
        )
        with self.assertRaisesRegex(ConfigEditorError, "没有有限实际样本"):
            propose_box_threshold(
                self.series,
                empty_box,
                accepted_preview_point_ids=("PT_1", "PT-1"),
            )

        with self.assertRaisesRegex(ConfigEditorError, "有限数值"):
            ThresholdSelectionBox(
                "deflection",
                "PT_1",
                LOWER_SIDE,
                "2026-01-01 00:00:00",
                "2026-01-01 03:00:00",
                float("nan"),
                30,
            ).validated()

        nonfinite_series = PreviewSeries(
            "deflection",
            "PT-1",
            "deflection",
            self.series.times,
            (None, float("nan"), float("inf"), float("-inf")),
        )
        with self.assertRaisesRegex(ConfigEditorError, "没有有限实际样本"):
            propose_box_threshold(
                nonfinite_series,
                ThresholdSelectionBox(
                    "deflection",
                    "PT_1",
                    UPPER_SIDE,
                    "2026-01-01 00:00:00",
                    "2026-01-01 03:00:00",
                    -100,
                    100,
                ),
                accepted_preview_point_ids=("PT_1", "PT-1"),
            )

        with self.assertRaisesRegex(ConfigEditorError, "不一致"):
            propose_box_threshold(
                self.series,
                ThresholdSelectionBox(
                    "acceleration",
                    "PT_1",
                    LOWER_SIDE,
                    "2026-01-01 00:00:00",
                    "2026-01-01 03:00:00",
                    -100,
                    100,
                ),
                accepted_preview_point_ids=("PT_1", "PT-1"),
            )

    def test_box_apply_updates_one_side_in_place_and_preserves_rule_scope(self) -> None:
        rows = [
            CleaningThresholdRow(
                "per_point",
                "deflection",
                "PT_1",
                -10,
                10,
                "2026-01-01 01:00:00",
                "2026-01-01 02:00:00",
                False,
                30,
                3,
            )
        ]
        lower = OneSidedThresholdDraft(
            "deflection",
            "PT_1",
            LOWER_SIDE,
            -2,
            "2026-01-01 00:00:00",
            "2026-01-01 03:00:00",
        )
        merged, index, replaced = apply_one_sided_to_selected_row(
            rows, selected_index=0, draft=lower
        )
        self.assertTrue(replaced)
        self.assertEqual(index, 0)
        self.assertEqual(len(merged), 1)
        self.assertEqual((merged[0].minimum, merged[0].maximum), (-2, 10))
        self.assertEqual(
            (merged[0].t_range_start, merged[0].t_range_end),
            ("2026-01-01 01:00:00", "2026-01-01 02:00:00"),
        )
        self.assertFalse(merged[0].zero_to_nan)
        self.assertEqual(merged[0].outlier_window_sec, 30)
        self.assertEqual(merged[0].outlier_threshold_factor, 3)

        upper = OneSidedThresholdDraft("deflection", "PT_1", UPPER_SIDE, 6)
        merged, _, _ = apply_one_sided_to_selected_row(
            merged, selected_index=0, draft=upper
        )
        self.assertEqual((merged[0].minimum, merged[0].maximum), (-2, 6))

        with self.assertRaisesRegex(ConfigEditorError, "下限.*上限"):
            apply_one_sided_to_selected_row(
                rows,
                selected_index=0,
                draft=OneSidedThresholdDraft(
                    "deflection", "PT_1", LOWER_SIDE, 11
                ),
            )
        with self.assertRaisesRegex(ConfigEditorError, "上限.*下限"):
            apply_one_sided_to_selected_row(
                rows,
                selected_index=0,
                draft=OneSidedThresholdDraft(
                    "deflection", "PT_1", UPPER_SIDE, -11
                ),
            )
        with self.assertRaisesRegex(ConfigEditorError, "严格小于"):
            apply_one_sided_to_selected_row(
                rows,
                selected_index=0,
                draft=OneSidedThresholdDraft(
                    "deflection", "PT_1", LOWER_SIDE, 10
                ),
            )
        with self.assertRaisesRegex(ConfigEditorError, "严格大于"):
            apply_one_sided_to_selected_row(
                rows,
                selected_index=0,
                draft=OneSidedThresholdDraft(
                    "deflection", "PT_1", UPPER_SIDE, -10
                ),
            )


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

    def test_two_line_curve_drags_bound_and_shared_time_window(self) -> None:
        curve = ThresholdBandCurveView()
        curve.resize(760, 440)
        curve.set_rule(self.series(), lower=2, upper=8)
        bounds: list[tuple[float, float]] = []
        windows: list[tuple[str, str]] = []
        curve.bounds_changed.connect(lambda low, high: bounds.append((low, high)))
        curve.window_changed.connect(lambda start, end: windows.append((start, end)))
        curve.show()
        self.app.processEvents()
        frame = curve._frame()
        lower_y = curve._pixel_y(2)
        target_y = curve._pixel_y(4)
        QTest.mousePress(
            curve,
            Qt.LeftButton,
            Qt.NoModifier,
            QPoint(int(frame.center().x()), int(lower_y)),
        )
        QTest.mouseMove(curve, QPoint(int(frame.center().x()), int(target_y)), 5)
        QTest.mouseRelease(
            curve,
            Qt.LeftButton,
            Qt.NoModifier,
            QPoint(int(frame.center().x()), int(target_y)),
        )
        self.app.processEvents()
        self.assertTrue(bounds)
        self.assertAlmostEqual(bounds[-1][0], 4, delta=0.3)
        self.assertAlmostEqual(bounds[-1][1], 8, delta=0.3)

        start, _end, _ = curve._window_values()
        new_start_x = frame.left() + frame.width() * 0.25
        middle_y = (curve._pixel_y(curve._lower) + curve._pixel_y(curve._upper)) / 2
        QTest.mousePress(
            curve,
            Qt.LeftButton,
            Qt.NoModifier,
            QPoint(int(curve._pixel_x(start)), int(middle_y)),
        )
        QTest.mouseMove(curve, QPoint(int(new_start_x), int(middle_y)), 5)
        QTest.mouseRelease(
            curve,
            Qt.LeftButton,
            Qt.NoModifier,
            QPoint(int(new_start_x), int(middle_y)),
        )
        self.app.processEvents()
        try:
            self.assertTrue(windows)
            self.assertLess(windows[-1][0], windows[-1][1])
        finally:
            curve.close()

    def test_band_requires_preview_and_reset_restores_legacy_window(self) -> None:
        target = CleaningThresholdRow(
            "per_point",
            "deflection",
            "PT_1",
            -3,
            9,
            "2026-01-01 00:01:00",
            "2026-01-01 00:04:00",
        )
        no_preview = ThresholdBandDialog(
            target,
            accepted_preview_point_ids=("PT_1",),
        )
        try:
            self.assertFalse(no_preview.accept_button.isEnabled())
            self.assertTrue(no_preview.time_window_check.isChecked())
            self.assertFalse(no_preview.time_window_check.isEnabled())
        finally:
            no_preview.close()

        dialog = ThresholdBandDialog(
            target,
            accepted_preview_point_ids=("PT_1",),
            preview_series=self.series(),
        )
        try:
            self.assertTrue(dialog.accept_button.isEnabled())
            dialog.lower_edit.setText("-1")
            dialog.upper_edit.setText("6")
            dialog.start_edit.setDateTime(
                QDateTime.fromString("2026-01-01 00:02:00", "yyyy-MM-dd HH:mm:ss")
            )
            dialog.end_edit.setDateTime(
                QDateTime.fromString("2026-01-01 00:03:00", "yyyy-MM-dd HH:mm:ss")
            )
            dialog._reset()
            restored = dialog.draft()
            self.assertEqual((restored.lower, restored.upper), (-3, 9))
            self.assertEqual(
                (restored.t_range_start, restored.t_range_end),
                ("2026-01-01 00:01:00", "2026-01-01 00:04:00"),
            )
        finally:
            dialog.close()

        blank = ThresholdBandDialog(
            CleaningThresholdRow("per_point", "deflection", "PT_1", None, None),
            accepted_preview_point_ids=("PT_1",),
            preview_series=self.series(),
        )
        try:
            generated = blank.draft()
            self.assertEqual(
                (generated.t_range_start, generated.t_range_end),
                ("2026-01-01 00:00:00", "2026-01-01 00:05:00"),
            )
        finally:
            blank.close()

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

    def test_box_dialog_uses_actual_selected_samples_and_explicit_rule_text(self) -> None:
        target = CleaningThresholdRow("per_point", "deflection", "PT_1", None, None)
        dialog = BoxThresholdDialog(
            target,
            side=LOWER_SIDE,
            accepted_preview_point_ids=("PT_1",),
            preview_series=self.series(),
        )
        try:
            dialog.show()
            self.app.processEvents()
            curve = dialog.curve
            x0 = curve._pixel_x(datetime(2026, 1, 1, 0, 0).timestamp())
            x2 = curve._pixel_x(datetime(2026, 1, 1, 0, 2).timestamp())
            top = curve._pixel_y(4.5)
            bottom = curve._pixel_y(-0.5)
            QTest.mousePress(
                curve, Qt.LeftButton, Qt.NoModifier, QPoint(int(x0 + 1), int(top))
            )
            QTest.mouseMove(curve, QPoint(int(x2 + 1), int(bottom)), 5)
            QTest.mouseRelease(
                curve, Qt.LeftButton, Qt.NoModifier, QPoint(int(x2 + 1), int(bottom))
            )
            self.app.processEvents()
            proposal = dialog.proposal()
            self.assertEqual(proposal.threshold, 4.0)
            self.assertGreaterEqual(proposal.selected_sample_count, 2)
            self.assertIn("下侧框选取框中实际有限样本的最高值", dialog.findChildren(QLabel)[1].text())
            self.assertIn("框中最高值", dialog.summary_label.text())
            self.assertIn("等于该值的点保留", dialog.summary_label.text())
            self.assertTrue(dialog.accept_button.isEnabled())
        finally:
            dialog.close()

    def test_box_dialog_estimates_final_rule_with_existing_opposite_bound(self) -> None:
        target = CleaningThresholdRow(
            "per_point", "deflection", "PT_1", None, 7
        )
        dialog = BoxThresholdDialog(
            target,
            side=LOWER_SIDE,
            accepted_preview_point_ids=("PT_1",),
            preview_series=self.series(),
        )
        try:
            dialog._selection_changed(
                ThresholdSelectionBox(
                    "deflection",
                    "PT_1",
                    LOWER_SIDE,
                    "2026-01-01 00:00:00",
                    "2026-01-01 00:02:00",
                    -1,
                    4,
                )
            )
            self.assertEqual(dialog.proposal().threshold, 4)
            self.assertIsNotNone(dialog.current_final_estimate)
            assert dialog.current_final_estimate is not None
            self.assertEqual(dialog.current_final_estimate.removed_count, 4)
            self.assertIn("最终规则估算", dialog.summary_label.text())
        finally:
            dialog.close()

    def test_box_curve_keeps_subsecond_hit_set_exact(self) -> None:
        series = PreviewSeries(
            "deflection",
            "PT_1",
            "deflection",
            (
                "2026-01-01 00:00:00.100000",
                "2026-01-01 00:00:00.200000",
                "2026-01-01 00:00:00.300000",
                "2026-01-01 00:00:00.400000",
            ),
            (2.0, 2.0, 2.0, 2.0),
        )
        curve = BoxThresholdCurveView()
        curve.resize(760, 440)
        curve.set_series(
            series,
            side=LOWER_SIDE,
            module_key="deflection",
            point_key="PT_1",
        )
        curve.show()
        self.app.processEvents()
        try:
            target = curve._sample_points()[1][3]
            curve._finish_selection(
                QRectF(target.x() - 3, target.y() - 8, 6, 16)
            )
            selection = curve.selection()
            self.assertIsNotNone(selection)
            assert selection is not None
            self.assertEqual(curve.selected_indices(), (1,))
            self.assertEqual(
                selection.selection_start,
                "2026-01-01 00:00:00.200000",
            )
            self.assertEqual(selection.selection_start, selection.selection_end)
            proposal = propose_box_threshold(
                series,
                selection,
                accepted_preview_point_ids=("PT_1",),
            )
            self.assertEqual(proposal.selected_sample_count, 1)
            self.assertEqual(proposal.threshold, 2.0)
        finally:
            curve.close()

    def test_cleaning_page_exposes_and_routes_band_and_two_box_entries(self) -> None:
        expected_context = {
            "bridge_id": "unit_bridge",
            "data_root": str(Path.cwd()),
            "start_date": "2026-01-01",
            "end_date": "2026-01-31",
        }
        widget = CleaningThresholdEditorWidget(
            preview_context_provider=lambda: dict(expected_context)
        )
        widget.load_path(FIXTURE)
        point_row = next(
            index
            for index in range(widget.table.rowCount())
            if widget.table.item(index, 2).text() == "PT_1"
        )
        routed: list[str] = []
        routed_contexts: list[dict[str, object]] = []

        class RejectedBandDialog:
            def __init__(self, _target: CleaningThresholdRow, **kwargs: object) -> None:
                routed.append("band")
                routed_contexts.append(kwargs)

            def exec(self) -> int:
                return QDialog.Rejected

        class RejectedBoxDialog:
            def __init__(
                self, _target: CleaningThresholdRow, *, side: str, **kwargs: object
            ) -> None:
                routed.append(side)
                routed_contexts.append(kwargs)

            def exec(self) -> int:
                return QDialog.Rejected

        try:
            widget.resize(1500, 900)
            widget.show()
            widget.table.selectRow(point_row)
            widget.threshold_band_dialog_class = RejectedBandDialog
            widget.box_threshold_dialog_class = RejectedBoxDialog
            self.app.processEvents()

            self.assertEqual(widget.manual_threshold_group.objectName(), "manualThresholdGroup")
            self.assertIn("沿用旧 MATLAB GUI", widget.manual_threshold_entry_label.text())
            self.assertIn("下侧框选取框中实际样本的最高值", widget.manual_threshold_entry_label.text())
            self.assertIn("上侧框选取框中实际样本的最低值", widget.manual_threshold_entry_label.text())
            self.assertIn("拖线设置上下限", widget.threshold_band_button.text())
            self.assertIn("下侧框选取最高值", widget.lower_box_threshold_button.text())
            self.assertIn("上侧框选取最低值", widget.upper_box_threshold_button.text())
            self.assertEqual(
                widget.threshold_band_button.objectName(), "openThresholdBandCurveButton"
            )
            self.assertEqual(
                widget.lower_box_threshold_button.objectName(), "openLowerBoxThresholdButton"
            )
            self.assertEqual(
                widget.upper_box_threshold_button.objectName(), "openUpperBoxThresholdButton"
            )

            QTest.mouseClick(widget.threshold_band_button, Qt.LeftButton)
            QTest.mouseClick(widget.lower_box_threshold_button, Qt.LeftButton)
            QTest.mouseClick(widget.upper_box_threshold_button, Qt.LeftButton)
            self.app.processEvents()
            self.assertEqual(routed, ["band", LOWER_SIDE, UPPER_SIDE])
            for context in routed_contexts:
                self.assertEqual(context["expected_bridge_id"], "unit_bridge")
                self.assertEqual(context["expected_data_root"], str(Path.cwd()))
                self.assertEqual(context["expected_start_date"], "2026-01-01")
                self.assertEqual(context["expected_end_date"], "2026-01-31")

            with tempfile.TemporaryDirectory() as temp_dir:
                screenshot = Path(temp_dir) / "manual_threshold_entry.png"
                pixmap = widget.grab()
                self.assertFalse(pixmap.isNull())
                self.assertTrue(pixmap.save(str(screenshot)))
                self.assertGreater(screenshot.stat().st_size, 10_000)
        finally:
            widget.close()

    def test_both_curve_dialogs_reject_legacy_preview_when_task_is_bound(self) -> None:
        target = CleaningThresholdRow(
            "per_point", "deflection", "PT_1", -1.0, 11.0
        )
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            preview_path = root / "legacy_preview.json"
            preview_path.write_text(
                json.dumps(
                    {
                        "schema_version": 1,
                        "artifact_type": "auto_threshold_preview",
                        "request_type": "auto_threshold_proposal",
                        "request_id": "legacy",
                        "config_sha256": "c" * 64,
                        "preview_series": [],
                    }
                ),
                encoding="utf-8",
            )
            common = {
                "accepted_preview_point_ids": ("PT_1",),
                "expected_bridge_id": "unit_bridge",
                "expected_data_root": str(root),
                "expected_start_date": "2026-01-01",
                "expected_end_date": "2026-01-31",
            }
            band = ThresholdBandDialog(target, **common)
            box = BoxThresholdDialog(target, side=LOWER_SIDE, **common)
            try:
                with self.assertRaisesRegex(ThresholdCurveError, "重新生成当前测点曲线"):
                    band.load_preview_path(preview_path)
                with self.assertRaisesRegex(ThresholdCurveError, "重新生成当前测点曲线"):
                    box.load_preview_path(preview_path)
            finally:
                band.close()
                box.close()

    def test_cleaning_page_applies_band_and_box_in_memory_then_undoes(self) -> None:
        widget = CleaningThresholdEditorWidget()
        widget.load_path(FIXTURE)
        point_row = next(
            index
            for index in range(widget.table.rowCount())
            if widget.table.item(index, 2).text() == "PT_1"
        )

        class AcceptedBandDialog:
            def __init__(self, target: CleaningThresholdRow, **_kwargs: object) -> None:
                self._draft = TwoSidedThresholdDraft(
                    target.module_key, target.point_key, -2.5004, 7.5006
                )

            def exec(self) -> int:
                return QDialog.Accepted

            def draft(self) -> TwoSidedThresholdDraft:
                return self._draft

            def estimate_summary(self) -> str:
                return "基于预览估计；正式值需使用完整缓存复算"

        class CancelledBandDialog(AcceptedBandDialog):
            def exec(self) -> int:
                return QDialog.Rejected

        class AcceptedBoxDialog:
            def __init__(
                self, target: CleaningThresholdRow, *, side: str, **_kwargs: object
            ) -> None:
                value = -1.25 if side == LOWER_SIDE else 6.25
                draft = OneSidedThresholdDraft(
                    target.module_key, target.point_key, side, value
                )
                self._proposal = BoxThresholdProposal(
                    draft,
                    3,
                    estimate_one_sided_rule(
                        self.series(),
                        draft,
                        accepted_preview_point_ids=("PT_1",),
                    ),
                )

            @staticmethod
            def series() -> PreviewSeries:
                return ManualThresholdGuiTests.series()

            def exec(self) -> int:
                return QDialog.Accepted

            def proposal(self) -> BoxThresholdProposal:
                return self._proposal

            def estimate_summary(self) -> str:
                return self._proposal.estimate.summary_text()

        try:
            widget.table.selectRow(point_row)
            before = widget.rows()
            source_before = FIXTURE.read_bytes()
            widget.threshold_band_dialog_class = CancelledBandDialog
            widget.open_threshold_band()
            self.assertEqual(widget.rows(), before)

            widget.threshold_band_dialog_class = AcceptedBandDialog
            widget.open_threshold_band()
            self.assertEqual(widget.table.rowCount(), len(before))
            changed = widget.rows()[point_row]
            self.assertEqual((changed.minimum, changed.maximum), (-2.5, 7.501))
            self.assertIn("尚未保存", widget.message_label.text())
            self.assertTrue(widget.undo_manual_threshold_button.isEnabled())
            self.assertEqual(FIXTURE.read_bytes(), source_before)

            widget.box_threshold_dialog_class = AcceptedBoxDialog
            widget.open_box_threshold(LOWER_SIDE)
            self.assertEqual(widget.rows()[point_row].minimum, -1.25)
            self.assertEqual(widget.rows()[point_row].maximum, 7.501)
            self.assertIn("下侧框选取最高值", widget.message_label.text())
            self.assertEqual(FIXTURE.read_bytes(), source_before)

            widget.undo_manual_threshold()
            self.assertEqual(
                (widget.rows()[point_row].minimum, widget.rows()[point_row].maximum),
                (-2.5, 7.501),
            )
            self.assertFalse(widget.undo_manual_threshold_button.isEnabled())
        finally:
            widget.close()

    def test_curve_undo_expires_after_manual_table_edit(self) -> None:
        widget = CleaningThresholdEditorWidget()
        widget.load_path(FIXTURE)
        point_row = next(
            index
            for index in range(widget.table.rowCount())
            if widget.table.item(index, 2).text() == "PT_1"
        )

        class AcceptedBandDialog:
            def __init__(self, target: CleaningThresholdRow, **_kwargs: object) -> None:
                self._draft = TwoSidedThresholdDraft(
                    target.module_key,
                    target.point_key,
                    -2.5,
                    7.5,
                    "2026-01-01 00:00:00",
                    "2026-01-01 00:05:00",
                )

            def exec(self) -> int:
                return QDialog.Accepted

            def draft(self) -> TwoSidedThresholdDraft:
                return self._draft

            def estimate_summary(self) -> str:
                return "完整缓存复算"

        try:
            widget.table.selectRow(point_row)
            widget.threshold_band_dialog_class = AcceptedBandDialog
            widget.open_threshold_band()
            self.assertTrue(widget.undo_manual_threshold_button.isEnabled())
            widget.table.item(point_row, 3).setText("-2.25")
            self.app.processEvents()
            self.assertFalse(widget.undo_manual_threshold_button.isEnabled())
            self.assertEqual(widget.rows()[point_row].minimum, -2.25)
            widget.undo_manual_threshold()
            self.assertEqual(widget.rows()[point_row].minimum, -2.25)
        finally:
            widget.close()

    def test_post_filter_page_exposes_only_explicit_fig_curve_tools(self) -> None:
        widget = PostFilterThresholdEditorWidget()
        try:
            self.assertTrue(widget.supports_curve_threshold_tools)
            self.assertFalse(widget.supports_task_curve_preview)
            self.assertTrue(hasattr(widget, "manual_threshold_group"))

            target = CleaningThresholdRow(
                "per_point", "acceleration", "PT-1", -1.0, 1.0
            )
            dialog = ThresholdBandDialog(
                target,
                accepted_preview_point_ids=("PT-1",),
                task_preview_enabled=False,
            )
            try:
                self.assertFalse(dialog.direct_fig_button.isHidden())
                self.assertTrue(dialog.auto_load_preview_button.isHidden())
                self.assertTrue(dialog.import_preview_button.isHidden())
                self.assertTrue(dialog.generate_preview_button.isHidden())
                self.assertIn("MATLAB FIG", dialog.preview_path_label.text())
            finally:
                dialog.close()
        finally:
            widget.close()


if __name__ == "__main__":
    unittest.main()
