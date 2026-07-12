from __future__ import annotations

import copy
import os
import unittest
from pathlib import Path
from unittest.mock import patch

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

from workbench.config_editor import ConfigEditorError
from workbench.plot_config import (
    PLOT_COMMON_SCHEMA,
    SPECTRUM_MODULES,
    PlotCommonConfigSession,
    PlotCommonRow,
    SpectrumConfigSession,
    SpectrumCoverage,
    SpectrumPeakOrderRow,
    apply_plot_common,
    apply_spectrum_config,
)

try:
    from PySide6.QtWidgets import QApplication

    from workbench.plot_config_tab import (
        PlotCommonEditorWidget,
        SpectrumConfigEditorWidget,
    )
except ImportError:  # pragma: no cover
    QApplication = None
    PlotCommonEditorWidget = None
    SpectrumConfigEditorWidget = None


ROOT = Path(__file__).resolve().parents[1]
CONFIGS = (
    "default_config.json",
    "hongtang_config.json",
    "jiulongjiang_config.json",
    "shuixianhua_config.json",
    "chongyangxi_config.json",
    "zhishan_config.json",
)
FIXTURE = ROOT / "tests" / "fixtures" / "workbench_plot_spectrum_contract.json"


class WorkbenchPlotCommonTests(unittest.TestCase):
    def test_all_bridge_plot_common_noop_round_trip(self) -> None:
        for name in CONFIGS:
            with self.subTest(name=name):
                session = PlotCommonConfigSession(ROOT / "config" / name)
                self.assertEqual(session.build_payload(session.rows), session.payload)

    def test_shared_matlab_contract_fixture_round_trips(self) -> None:
        session = PlotCommonConfigSession(FIXTURE)
        self.assertEqual(session.build_payload(session.rows), session.payload)
        values = {row.field: row.value for row in session.rows}
        self.assertEqual(values["dynamic_raw_sampling_mode"], "full")
        self.assertEqual(values["dynamic_raw_band_bins"], 48000)

    def test_plot_edit_preserves_unknown_fields_and_can_remove_explicit(self) -> None:
        payload = {
            "plot_common": {
                "save_fig": True,
                "fig_max_points": 50000,
                "future_plot_option": "keep",
            },
            "other": {"keep": True},
        }
        session_rows = PlotCommonConfigSession(FIXTURE).rows
        rows = [
            PlotCommonRow(
                row.field,
                row.value_type,
                False if row.field == "save_fig" else row.explicit,
                75000 if row.field == "fig_max_points" else row.value,
                row.description,
            )
            for row in session_rows
        ]
        updated = apply_plot_common(payload, rows)
        self.assertNotIn("save_fig", updated["plot_common"])
        self.assertEqual(updated["plot_common"]["fig_max_points"], 75000)
        self.assertEqual(updated["plot_common"]["future_plot_option"], "keep")
        self.assertTrue(updated["other"]["keep"])

    def test_full_sampling_rejects_explicit_dense_band(self) -> None:
        rows = []
        for field, value_type, default, description in PLOT_COMMON_SCHEMA:
            value = default
            explicit = field in {"dynamic_raw_sampling_mode", "dynamic_raw_render_mode"}
            if field == "dynamic_raw_sampling_mode":
                value = "full"
            if field == "dynamic_raw_render_mode":
                value = "dense_band"
            rows.append(PlotCommonRow(field, value_type, explicit, value, description))
        with self.assertRaisesRegex(ConfigEditorError, "强制 line"):
            apply_plot_common({}, rows)


class WorkbenchSpectrumConfigTests(unittest.TestCase):
    def test_all_bridge_spectrum_configs_noop_round_trip(self) -> None:
        for name in CONFIGS:
            with self.subTest(name=name):
                session = SpectrumConfigSession(ROOT / "config" / name)
                coverages = {
                    module: session.coverage(module) for module in SPECTRUM_MODULES
                }
                orders = {module: session.orders(module) for module in SPECTRUM_MODULES}
                self.assertEqual(
                    session.build_payload_all(coverages, orders), session.payload
                )

    def test_shared_contract_reads_explicit_coverage_and_legacy_point_order(self) -> None:
        session = SpectrumConfigSession(FIXTURE)
        coverage = session.coverage("accel_spectrum")
        rows = session.orders("accel_spectrum")
        self.assertTrue(coverage.explicit)
        self.assertEqual(coverage.points, ("A-1", "A-2"))
        self.assertEqual(len(rows), 3)
        a1 = next(row for row in rows if row.point_id == "A-1")
        self.assertEqual(a1.source, "per_point_legacy")
        self.assertAlmostEqual(a1.search_min_hz, 0.62)
        self.assertAlmostEqual(a1.search_max_hz, 0.68)

    def test_edit_migrates_frequency_fields_but_preserves_thresholds_and_fs(self) -> None:
        session = SpectrumConfigSession(FIXTURE)
        coverage = session.coverage("accel_spectrum")
        rows = session.orders("accel_spectrum")
        updated = apply_spectrum_config(session.payload, coverage, rows)
        params = updated["accel_spectrum_params"]
        self.assertEqual(params["fs"], 20)
        self.assertIn("peak_orders", params)
        self.assertNotIn("target_freqs", params)
        a1 = updated["per_point"]["accel_spectrum"]["A_1"]
        a2 = updated["per_point"]["accel_spectrum"]["A_2"]
        self.assertIn("peak_orders", a1)
        self.assertNotIn("target_freqs", a1)
        self.assertEqual(a2["thresholds"], {"min": -10, "max": 10})
        self.assertTrue(updated["unrelated_marker"]["keep"])

    def test_coverage_can_fall_back_or_become_explicit(self) -> None:
        payload = {
            "points": {"acceleration": ["A1", "A2"]},
            "accel_spectrum_params": {},
        }
        fallback = SpectrumCoverage("accel_spectrum", False, ("A1", "A2"))
        updated = apply_spectrum_config(payload, fallback, [])
        self.assertNotIn("accel_spectrum", updated["points"])
        explicit = SpectrumCoverage("accel_spectrum", True, ("A2",))
        updated = apply_spectrum_config(payload, explicit, [])
        self.assertEqual(updated["points"]["accel_spectrum"], ["A2"])

    def test_duplicate_orders_and_unknown_point_are_rejected(self) -> None:
        payload = {
            "points": {"acceleration": ["A1"]},
            "accel_spectrum_params": {},
        }
        coverage = SpectrumCoverage("accel_spectrum", True, ("A1",))
        row = SpectrumPeakOrderRow(
            "accel_spectrum", "point", "A1", 1, "一阶", None, 0.5, 0.7
        )
        with self.assertRaisesRegex(ConfigEditorError, "重复"):
            apply_spectrum_config(payload, coverage, [row, copy.copy(row)])
        unknown = SpectrumPeakOrderRow(
            "accel_spectrum", "point", "A404", 1, "一阶", None, 0.5, 0.7
        )
        with self.assertRaisesRegex(ConfigEditorError, "未知测点"):
            apply_spectrum_config(payload, coverage, [unknown])


@unittest.skipIf(QApplication is None, "PySide6 is not installed")
class WorkbenchPlotSpectrumGuiTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.app = QApplication.instance() or QApplication([])

    def test_plot_common_widget_shows_all_production_fields(self) -> None:
        widget = PlotCommonEditorWidget()
        widget.load_path(ROOT / "config" / "hongtang_config.json")
        self.assertEqual(widget.table.rowCount(), 14)
        self.assertEqual(widget.rows(), widget.session.rows)
        fields = {widget.table.item(row, 1).text() for row in range(widget.table.rowCount())}
        self.assertIn("dynamic_raw_line_width", fields)
        self.assertIn("dynamic_raw_render_mode", fields)

    def test_spectrum_widget_loads_zhishan_coverage_and_orders(self) -> None:
        widget = SpectrumConfigEditorWidget()
        widget.load_path(ROOT / "config" / "zhishan_config.json")
        self.assertEqual(widget.module_combo.count(), 2)
        self.assertEqual(widget.selected_points.count(), 5)
        self.assertEqual(widget.order_table.rowCount(), 6)
        coverages, orders = widget._drafts()
        self.assertEqual(
            widget.session.build_payload_all(coverages, orders), widget.session.payload
        )

    def test_invalid_order_blocks_module_switch_without_losing_draft(self) -> None:
        widget = SpectrumConfigEditorWidget()
        widget.load_path(ROOT / "config" / "zhishan_config.json")
        widget.order_table.item(0, 6).setText("不是数字")
        with patch("workbench.plot_config_tab.QMessageBox.critical") as critical:
            widget.module_combo.setCurrentIndex(1)
        critical.assert_called_once()
        self.assertEqual(widget.module_combo.currentIndex(), 0)
        self.assertEqual(widget.loaded_module, "accel_spectrum")
        self.assertEqual(widget.order_table.item(0, 6).text(), "不是数字")


if __name__ == "__main__":
    unittest.main()
