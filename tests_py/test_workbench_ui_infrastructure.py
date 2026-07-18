from __future__ import annotations

import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

try:
    from PySide6.QtCore import QPoint, QRect, QSettings, QSize, Qt
    from PySide6.QtTest import QTest
    from PySide6.QtWidgets import (
        QApplication,
        QPushButton,
        QScrollArea,
        QTableWidgetSelectionRange,
    )

    from workbench.copyable_table import CopyableTableWidget
    from workbench.main_window import (
        WorkbenchWindow,
        _provenance_detail_text,
        _whole_seconds_text,
    )
    from workbench.module_progress import ModuleProgressSnapshot, ModuleProgressStep
    from workbench.module_progress_widget import ModuleProgressPanel, _elapsed_text
    from workbench.provenance import PlotProvenanceRow
    from workbench.ui_styles import apply_danger_action_style
    from workbench.window_geometry import (
        fit_window_geometry,
        saved_geometry_is_legal,
    )
except ImportError:  # pragma: no cover - dependency gate
    QApplication = None


@unittest.skipIf(QApplication is None, "PySide6 is not installed")
class CopyableTableTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.app = QApplication.instance() or QApplication([])

    def test_rectangular_copy_tooltips_details_and_paths(self) -> None:
        table = CopyableTableWidget(2, 3)
        with tempfile.TemporaryDirectory() as folder:
            file_path = Path(folder) / "统计 结果.xlsx"
            file_path.write_bytes(b"test")
            table.set_copyable_item(0, 0, "A")
            table.set_copyable_item(0, 1, "很长的说明")
            table.set_copyable_item(0, 2, file_path, path=file_path)
            table.set_copyable_item(1, 0, "B")
            table.set_copyable_item(1, 1, "第二行")
            table.set_copyable_item(1, 2, "")
            table.setRangeSelected(QTableWidgetSelectionRange(0, 0, 1, 1), True)

            self.assertEqual(table.copy_selected_as_tsv(), "A\t很长的说明\nB\t第二行")
            self.assertEqual(QApplication.clipboard().text(), "A\t很长的说明\nB\t第二行")
            table.show()
            QApplication.processEvents()
            QTest.keyClick(table, Qt.Key_C, Qt.ControlModifier)
            self.assertEqual(QApplication.clipboard().text(), "A\t很长的说明\nB\t第二行")
            self.assertEqual(table.item(0, 1).toolTip(), "很长的说明")
            self.assertEqual(table.copy_full_path(0, 2), str(file_path))
            self.assertEqual(table.copy_full_path(0, 0), str(file_path))

            with patch(
                "workbench.copyable_table.QDesktopServices.openUrl", return_value=True
            ) as open_url:
                self.assertTrue(table.open_path(0, 2))
                self.assertTrue(table.open_containing_directory(0, 2))
                self.assertEqual(open_url.call_count, 2)

            detail = table.show_cell_detail(0, 1)
            self.assertIsNotNone(detail)
            self.assertTrue(detail.text_edit.isReadOnly())
            self.assertEqual(detail.text_edit.toPlainText(), "很长的说明")
            self.assertTrue(detail.testAttribute(Qt.WA_DeleteOnClose))
            detail.close()
            QApplication.processEvents()
            self.assertEqual(table._detail_dialogs, [])

            cell_center = table.visualItemRect(table.item(0, 1)).center()
            table.setCurrentCell(0, 1)
            table.setFocus()
            QTest.mouseClick(table.viewport(), Qt.LeftButton, pos=cell_center)
            QTest.mouseDClick(table.viewport(), Qt.LeftButton, pos=cell_center)
            QApplication.processEvents()
            self.assertEqual(len(table._detail_dialogs), 1)
            self.assertEqual(
                table._detail_dialogs[0].text_edit.toPlainText(),
                "很长的说明",
            )
            table._detail_dialogs[0].close()
            QApplication.processEvents()

            menu = table.context_menu_for_cell(0, 1)
            action_states = {
                action.text(): action.isEnabled()
                for action in menu.actions()
                if action.text()
            }
            self.assertTrue(action_states["复制完整路径"])
            self.assertTrue(action_states["打开文件"])
            self.assertTrue(action_states["打开所在目录"])
            self.assertIn("查看只读详情", action_states)
            menu.close()
        table.close()

    def test_failed_and_gap_filters_are_composable(self) -> None:
        table = CopyableTableWidget(3, 1)
        for row, text in enumerate(("正常", "失败", "缺口")):
            table.set_copyable_item(row, 0, text)
        table.set_row_flags(0)
        table.set_row_flags(1, failed=True)
        table.set_row_flags(2, gap=True)

        table.set_filters(failed_only=True)
        self.assertEqual([table.isRowHidden(row) for row in range(3)], [True, False, True])
        table.set_filters(gap_only=True)
        self.assertEqual([table.isRowHidden(row) for row in range(3)], [True, True, False])
        table.set_filters(failed_only=True, gap_only=True)
        self.assertTrue(all(table.isRowHidden(row) for row in range(3)))
        table.close()

    def test_stop_buttons_share_enabled_and_disabled_danger_contract(self) -> None:
        button = QPushButton("请求停止")
        apply_danger_action_style(button)
        style = button.styleSheet()
        self.assertTrue(button.property("destructiveAction"))
        self.assertIn(":enabled:hover", style)
        self.assertIn(":enabled:pressed", style)
        self.assertIn(":disabled", style)
        self.assertIn("#a61b1b", style)
        self.assertIn("#d5d7da", style)
        button.close()

    def test_provenance_detail_prefers_structured_chinese_guidance(self) -> None:
        row = PlotProvenanceRow(
            module_key="wind",
            path=Path("W1.plot.json"),
            status="failed",
            series_count=1,
            source_count=144_400_712,
            plotted_count=12_032,
            incomplete_days=(),
            message="technical mismatch",
            failure_code="derived_count_mismatch",
            reason_zh="10 分钟派生点计数不闭合。",
            suggestion_zh="仅重算风模块后重新核验。",
        )
        self.assertEqual(
            _provenance_detail_text(row),
            "10 分钟派生点计数不闭合。\n修复建议：仅重算风模块后重新核验。",
        )

    def test_elapsed_display_uses_whole_seconds(self) -> None:
        self.assertEqual(_whole_seconds_text(6.1966939999982715), "6 秒")
        self.assertEqual(_whole_seconds_text(304.4322960000038), "304 秒")
        self.assertEqual(_whole_seconds_text(""), "")

    def test_module_elapsed_display_rejects_nonfinite_values(self) -> None:
        self.assertEqual(_elapsed_text(float("nan")), "")
        self.assertEqual(_elapsed_text(float("inf")), "")
        self.assertEqual(_elapsed_text(float("-inf")), "")

    def test_completed_module_progress_does_not_rebuild_unchanged_table(self) -> None:
        step = ModuleProgressStep(
            key="wind", label="风速风向分析", index=1, status="completed"
        )
        snapshot = ModuleProgressSnapshot(
            steps=(step,),
            completed_count=1,
            total_count=1,
            current_step=None,
            progress_fraction=1.0,
            authority="manifest",
            overall_status="completed",
        )
        panel = ModuleProgressPanel()
        try:
            panel.set_snapshot(snapshot)
            with patch.object(panel.table, "clearContents") as clear_contents:
                panel.set_snapshot(snapshot)
            clear_contents.assert_not_called()
        finally:
            panel.close()

    def test_dense_pages_can_shrink_and_scroll_on_short_screens(self) -> None:
        root = Path(__file__).resolve().parents[1]
        window = WorkbenchWindow(root)
        try:
            window.show()
            QApplication.processEvents()
            window.resize(900, 520)
            QApplication.processEvents()
            self.assertLessEqual(window.height(), 540)
            for object_name in (
                "analysisScrollArea",
                "reviewScrollArea",
                "reportScrollArea",
                "alarmConfigScrollArea",
                "cleaningConfigScrollArea",
                "autoThresholdConfigScrollArea",
            ):
                area = window.findChild(QScrollArea, object_name)
                self.assertIsNotNone(area, object_name)
                self.assertTrue(area.widgetResizable(), object_name)
        finally:
            window.poll_timer.stop()
            window.close()


@unittest.skipIf(QApplication is None, "PySide6 is not installed")
class WindowGeometryTests(unittest.TestCase):
    def test_default_geometry_is_centered_at_ninety_percent(self) -> None:
        result = fit_window_geometry(
            (QRect(0, 0, 1920, 1080),),
            anchor=QPoint(100, 100),
        )
        self.assertEqual(result, QRect(96, 54, 1728, 972))

    def test_default_geometry_stays_inside_common_windows_dpi_logical_screens(self) -> None:
        logical_screens = {
            "100%": QRect(0, 0, 1920, 1040),
            "125%": QRect(0, 0, 1536, 832),
            "150%": QRect(0, 0, 1280, 720),
        }
        for dpi_label, screen in logical_screens.items():
            with self.subTest(dpi=dpi_label):
                result = fit_window_geometry((screen,), anchor=screen.center())
                self.assertTrue(screen.contains(result))
                self.assertEqual(result.width(), round(screen.width() * 0.9))
                self.assertEqual(result.height(), round(screen.height() * 0.9))

    def test_saved_geometry_on_secondary_screen_is_preserved(self) -> None:
        screens = (QRect(0, 0, 1920, 1040), QRect(-1280, 0, 1280, 984))
        saved = QRect(-1200, 80, 1100, 800)
        self.assertTrue(saved_geometry_is_legal(saved, screens))
        self.assertEqual(
            fit_window_geometry(screens, saved=saved, anchor=QPoint(100, 100)),
            saved,
        )

    def test_partially_offscreen_saved_geometry_is_clamped_inside(self) -> None:
        screen = QRect(0, 0, 1536, 824)
        result = fit_window_geometry((screen,), saved=QRect(-40, 30, 1400, 780))
        self.assertEqual(result, QRect(0, 30, 1400, 780))
        self.assertTrue(screen.contains(result))

    def test_illegal_saved_geometry_falls_back_to_anchored_screen(self) -> None:
        screens = (QRect(0, 0, 1920, 1080), QRect(1920, 0, 2560, 1440))
        result = fit_window_geometry(
            screens,
            saved=QRect(9000, 9000, 1000, 700),
            anchor=QPoint(2500, 300),
            minimum_size=QSize(800, 600),
        )
        # A completely stale saved rectangle is discarded in favor of the
        # current pointer's screen.
        self.assertEqual(result, QRect(2048, 72, 2304, 1296))

    def test_main_window_persists_geometry_with_injected_settings(self) -> None:
        root = Path(__file__).resolve().parents[1]
        with tempfile.TemporaryDirectory() as folder:
            settings = QSettings(str(Path(folder) / "window.ini"), QSettings.IniFormat)
            window = WorkbenchWindow(root, window_settings=settings)
            screen = QApplication.primaryScreen().availableGeometry()
            expected = QRect(
                screen.left() + 10,
                screen.top() + 10,
                max(400, round(screen.width() * 0.7)),
                max(300, round(screen.height() * 0.7)),
            )
            window.setGeometry(expected)
            for button in (window.stop_btn, window.stop_report_btn):
                self.assertTrue(button.property("destructiveAction"))
                self.assertIn(":enabled:hover", button.styleSheet())
                self.assertIn(":disabled", button.styleSheet())
            window.close()
            settings.sync()
            self.assertIsNotNone(settings.value("window/geometry"))
            saved = settings.value("window/normal_geometry")
            self.assertIsInstance(saved, QRect)
            self.assertEqual(saved.size(), expected.size())

            restored = WorkbenchWindow(root, window_settings=settings)
            self.assertEqual(restored.size(), expected.size())
            self.assertLessEqual(abs(restored.x() - expected.x()), 20)
            self.assertLessEqual(abs(restored.y() - expected.y()), 20)
            self.assertTrue(screen.contains(restored.geometry()))
            restored.close()


if __name__ == "__main__":
    unittest.main()
