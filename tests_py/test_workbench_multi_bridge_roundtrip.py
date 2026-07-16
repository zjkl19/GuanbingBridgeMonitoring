from __future__ import annotations

import json
import os
import unittest
from pathlib import Path

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

from workbench.models import file_sha256

try:
    from PySide6.QtWidgets import QApplication

    from workbench.main_window import WorkbenchWindow
except ImportError:  # pragma: no cover - dependency gate
    QApplication = None
    WorkbenchWindow = None


ROOT = Path(__file__).resolve().parents[1]
EXPECTED_CONFIG_PAGES = (
    "预警值",
    "数据清洗阈值",
    "滤波后二次清洗",
    "自动清洗建议",
    "零点修正",
    "组图配置",
    "绘图公共参数",
    "频谱覆盖与找峰",
    "解压并发",
)


@unittest.skipIf(QApplication is None, "PySide6 is not installed")
class MultiBridgeConfigRoundTripTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.app = QApplication.instance() or QApplication([])

    def test_every_catalog_profile_loads_all_pages_and_round_trips_exactly(self) -> None:
        window = WorkbenchWindow(ROOT)
        config_paths = [profile.config_path(ROOT) for profile in window.profiles]
        before = {path: file_sha256(path) for path in config_paths}
        try:
            self.assertEqual(
                tuple(
                    window.config_tabs.tabText(index)
                    for index in range(window.config_tabs.count())
                ),
                EXPECTED_CONFIG_PAGES,
            )
            self.assertTrue(window.profiles)

            for index, profile in enumerate(window.profiles):
                with self.subTest(profile=profile.bridge_id):
                    window.profile_combo.setCurrentIndex(index)
                    self.app.processEvents()
                    config_path = profile.config_path(ROOT)
                    original = json.loads(config_path.read_text(encoding="utf-8-sig"))

                    editors = (
                        window.alarm_editor,
                        window.cleaning_editor,
                        window.post_filter_editor,
                        window.offset_editor,
                        window.group_plot_editor,
                        window.plot_common_editor,
                        window.spectrum_editor,
                        window.unzip_settings_editor,
                    )
                    self.assertTrue(
                        all(editor.session is not None for editor in editors),
                        "all eight config-backed pages must load",
                    )
                    self.assertTrue(
                        all(editor.session.path == config_path.resolve() for editor in editors)
                    )
                    context = window.auto_threshold_editor.context_provider()
                    self.assertEqual(Path(context["config_path"]), config_path)
                    self.assertEqual(context["bridge_id"], profile.bridge_id)
                    self.assertEqual(window.cleaning_editor._preview_context(), {
                        "bridge_id": profile.bridge_id,
                        "data_root": window.data_root_edit.text().strip(),
                        "config_path": str(config_path),
                        "start_date": window.start_date_edit.date().toString("yyyy-MM-dd"),
                        "end_date": window.end_date_edit.date().toString("yyyy-MM-dd"),
                    })

                    window.group_plot_editor._persist_module()
                    window.spectrum_editor._persist_module()
                    candidates = {
                        "alarm": window.alarm_editor.session.build_payload(
                            window.alarm_editor.rows()
                        ),
                        "cleaning": window.cleaning_editor.session.build_payload_all(
                            window.cleaning_editor.rows(),
                            window.cleaning_editor.exclude_rows(),
                        ),
                        "post_filter": window.post_filter_editor.session.build_payload(
                            window.post_filter_editor.rows()
                        ),
                        "offset": window.offset_editor.session.build_payload(
                            window.offset_editor.rows()
                        ),
                        "group": window.group_plot_editor.session.build_payload_all(
                            window.group_plot_editor.drafts
                        ),
                        "plot_common_and_gap": (
                            window.plot_common_editor.session.build_payload(
                                window.plot_common_editor.rows(),
                                window.plot_common_editor.gap_rows(),
                            )
                        ),
                        "spectrum": window.spectrum_editor.session.build_payload_all(
                            window.spectrum_editor.coverages,
                            window.spectrum_editor.order_drafts,
                        ),
                        "unzip": window.unzip_settings_editor.build_payload(),
                    }
                    for page, candidate in candidates.items():
                        self.assertEqual(candidate, original, page)

                    self.assertTrue(window.cleaning_editor.lower_threshold_button.isEnabled())
                    self.assertTrue(window.cleaning_editor.upper_threshold_button.isEnabled())
                    self.assertGreaterEqual(window.offset_editor.table.columnCount(), 7)
                    self.assertGreaterEqual(window.plot_common_editor.gap_table.columnCount(), 6)

            self.assertEqual(before, {path: file_sha256(path) for path in config_paths})
        finally:
            window.poll_timer.stop()
            window.auto_threshold_editor.poll_timer.stop()
            window.close()


if __name__ == "__main__":
    unittest.main()
