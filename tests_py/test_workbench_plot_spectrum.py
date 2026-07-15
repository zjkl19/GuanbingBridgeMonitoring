from __future__ import annotations

import copy
import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

from workbench.config_editor import ConfigEditorError
from workbench.plot_config import (
    PLOT_COMMON_SCHEMA,
    SPECTRUM_MODULES,
    GapOverrideRow,
    PlotCommonConfigSession,
    PlotCommonRow,
    SpectrumConfigSession,
    SpectrumCoverage,
    SpectrumPeakOrderRow,
    apply_gap_overrides,
    apply_plot_common,
    apply_spectrum_config,
    extract_gap_overrides,
    resolve_gap_options,
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
ACTIVE_SPECTRUM_CONFIGS = tuple(ROOT / "config" / name for name in CONFIGS) + (
    ROOT / "config" / "shuixianhua_layers" / "base.json",
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

    def test_all_bridge_gap_overrides_noop_round_trip(self) -> None:
        for name in CONFIGS:
            with self.subTest(name=name):
                session = PlotCommonConfigSession(ROOT / "config" / name)
                self.assertEqual(
                    session.build_payload(session.rows, session.gap_overrides),
                    session.payload,
                )

    def test_gap_precedence_is_point_module_legacy_global(self) -> None:
        payload = {
            "plot_common": {
                "gap_mode": "connect",
                "gap_break_factor": 5,
                "dynamic_raw_modules": {
                    "acceleration": {"gap_mode": "break", "gap_break_factor": 6}
                },
            },
            "plot_styles": {
                "acceleration": {"gap_mode": "connect", "line_width": 1.2}
            },
            "per_point": {
                "acceleration": {
                    "A_1": {
                        "plot": {"gap_mode": "break", "gap_break_factor": 9},
                        "thresholds": {"min": -1, "max": 1},
                    }
                }
            },
            "name_map_global": {"A_1": "A-1"},
        }
        point = resolve_gap_options(payload, "acceleration", "A-1")
        self.assertEqual(point["gap_mode"], "break")
        self.assertEqual(point["gap_break_factor"], 9)
        self.assertEqual(point["mode_source"], "测点设置")
        module = resolve_gap_options(payload, "acceleration", "A-2")
        self.assertEqual(module["gap_mode"], "connect")
        self.assertEqual(module["gap_break_factor"], 6)
        self.assertEqual(module["mode_source"], "模块设置")
        self.assertEqual(module["factor_source"], "兼容模块设置")
        legacy = resolve_gap_options(payload, "cable_accel", "CS1")
        self.assertEqual(legacy["gap_mode"], "connect")
        self.assertEqual(legacy["gap_break_factor"], 5)

    def test_gap_apply_preserves_unrelated_plot_and_point_fields(self) -> None:
        payload = {
            "plot_common": {"gap_mode": "connect", "gap_break_factor": 5},
            "plot_styles": {"strain": {"line_width": 1.5, "future": "keep"}},
            "per_point": {
                "strain": {"S_1": {"thresholds": {"min": -2, "max": 2}}}
            },
            "name_map_global": {"S_1": "S-1"},
            "other": {"keep": True},
        }
        rows = [
            GapOverrideRow("module", "strain", "", "break", 7),
            GapOverrideRow("point", "strain", "S-1", "connect", None),
        ]
        updated = apply_gap_overrides(payload, rows)
        self.assertEqual(updated["plot_styles"]["strain"]["line_width"], 1.5)
        self.assertEqual(updated["plot_styles"]["strain"]["future"], "keep")
        self.assertEqual(
            updated["per_point"]["strain"]["S_1"]["thresholds"],
            {"min": -2, "max": 2},
        )
        self.assertTrue(updated["other"]["keep"])
        self.assertEqual(extract_gap_overrides(updated), rows)
        self.assertEqual(resolve_gap_options(updated, "strain", "S-1")["gap_mode"], "connect")

    def test_gap_resolution_uses_real_module_key_before_compatibility_keys(self) -> None:
        payload = {
            "plot_common": {"gap_mode": "connect", "gap_break_factor": 5},
            "plot_styles": {
                "dynamic_strain": {"gap_mode": "break", "future": "keep"},
                "dynamic_strain_highpass": {"gap_mode": "connect"},
                "wind": {"gap_mode": "break"},
            },
            "per_point": {
                "dynamic_strain": {
                    "S1": {"plot": {"gap_break_factor": 8}}
                },
                "wind_speed": {"W1": {"plot": {"gap_mode": "connect"}}},
                "cable_accel": {"CS1": {"plot": {"gap_mode": "connect"}}},
            },
        }
        dynamic = resolve_gap_options(payload, "dynamic_strain_highpass", "S1")
        self.assertEqual(dynamic["gap_mode"], "connect")
        self.assertEqual(dynamic["gap_break_factor"], 8)
        wind = resolve_gap_options(payload, "wind", "W1")
        self.assertEqual(wind["gap_mode"], "connect")
        cable_spectrum = resolve_gap_options(payload, "cable_accel_spectrum", "CS1")
        self.assertEqual(cable_spectrum["gap_mode"], "connect")

    def test_gap_resolution_matches_shared_matlab_contract(self) -> None:
        payload = json.loads(
            (ROOT / "tests" / "fixtures" / "gap_override_contract.json").read_text(
                encoding="utf-8"
            )
        )
        for case in payload.pop("gap_resolution_cases"):
            with self.subTest(module=case["module_key"], point=case["point_id"]):
                resolved = resolve_gap_options(
                    payload, case["module_key"], case["point_id"]
                )
                self.assertEqual(resolved["gap_mode"], case["gap_mode"])
                self.assertEqual(
                    resolved["gap_break_factor"], case["gap_break_factor"]
                )

    def test_gap_duplicate_and_empty_inherit_are_rejected(self) -> None:
        self.assertEqual(apply_gap_overrides({"other": 1}, []), {"other": 1})
        row = GapOverrideRow("module", "strain", "", "break", None)
        with self.assertRaisesRegex(ConfigEditorError, "重复"):
            apply_gap_overrides({}, [row, row])
        with self.assertRaisesRegex(ConfigEditorError, "删除"):
            GapOverrideRow("module", "strain", "", "inherit", None).validated()


class WorkbenchSpectrumConfigTests(unittest.TestCase):
    def test_hongtang_acceleration_peak_bands_match_production_config(self) -> None:
        session = SpectrumConfigSession(ROOT / "config" / "hongtang_config.json")
        rows = session.orders("accel_spectrum")
        point_rows = {
            (row.point_id, int(row.order)): (row.search_min_hz, row.search_max_hz)
            for row in rows
            if row.scope == "point"
        }
        expected = {
            ("A1", 1): (0.783, 1.048),
            ("A1", 2): (1.428, 1.610),
            ("A1", 3): (2.587, 2.887),
            ("A5", 3): (2.384, 2.684),
            ("A9-X", 3): (2.416, 2.716),
            ("A9-Y", 3): (2.394, 2.694),
            ("A10-X", 1): (0.783, 1.022),
            ("A10-X", 3): (2.587, 2.887),
            ("A10-Y", 1): (0.783, 1.048),
            ("A10-Y", 2): (1.428, 1.686),
            ("A10-Y", 3): (2.296, 2.596),
        }
        for key, bounds in expected.items():
            with self.subTest(point=key[0], order=key[1]):
                self.assertAlmostEqual(point_rows[key][0], bounds[0], places=6)
                self.assertAlmostEqual(point_rows[key][1], bounds[1], places=6)

        for row in rows:
            if row.scope == "point":
                self.assertGreaterEqual(
                    row.search_min_hz,
                    (row.theoretical_hz or float("-inf")) + 0.05 - 1e-12,
                )
                self.assertLess(row.search_min_hz, row.search_max_hz)

    def test_active_configs_use_only_canonical_peak_orders(self) -> None:
        legacy_fields = {
            "target_freqs",
            "tolerance",
            "theor_freqs",
            "theor_labels",
            "peak_labels",
            "tolerance_hz",
        }
        for path in ACTIVE_SPECTRUM_CONFIGS:
            with self.subTest(name=str(path.relative_to(ROOT))):
                session = SpectrumConfigSession(path)
                payload = session.payload
                blocks = [
                    payload.get("accel_spectrum_params", {}),
                    payload.get("cable_accel_spectrum_params", {}),
                ]
                per_point = payload.get("per_point", {})
                blocks.extend((per_point.get("accel_spectrum", {}) or {}).values())
                blocks.extend((per_point.get("cable_accel", {}) or {}).values())
                for block in blocks:
                    if isinstance(block, dict):
                        self.assertTrue(legacy_fields.isdisjoint(block))
                for module in SPECTRUM_MODULES:
                    self.assertTrue(
                        all(
                            "legacy" not in row.source.casefold()
                            for row in session.orders(module)
                        )
                    )

    def test_all_bridge_spectrum_configs_noop_round_trip(self) -> None:
        for path in ACTIVE_SPECTRUM_CONFIGS:
            with self.subTest(name=str(path.relative_to(ROOT))):
                session = SpectrumConfigSession(path)
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
        self.assertEqual(a1.source, "兼容配置")
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
        fields = {row.field for row in widget.rows()}
        self.assertIn("dynamic_raw_line_width", fields)
        self.assertIn("dynamic_raw_render_mode", fields)
        labels = {widget.table.item(row, 1).text() for row in range(widget.table.rowCount())}
        self.assertIn("高频原始曲线线宽", labels)
        self.assertIn("高频原始图绘制方式", labels)
        tooltips = {
            widget.table.item(row, 1).toolTip()
            for row in range(widget.table.rowCount())
        }
        self.assertIn("高频原始曲线的线宽", tooltips)
        self.assertEqual(widget.gap_table.columnCount(), 6)

    def test_plot_common_widget_edits_gap_overrides_and_shows_effective_value(self) -> None:
        payload = json.loads(
            (ROOT / "config" / "hongtang_config.json").read_text(encoding="utf-8-sig")
        )
        payload.setdefault("plot_styles", {}).setdefault("acceleration", {})[
            "gap_mode"
        ] = "break"
        point = payload.setdefault("per_point", {}).setdefault("acceleration", {}).setdefault(
            "A1", {}
        )
        point["plot"] = {"gap_mode": "connect", "gap_break_factor": 8}
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "config.json"
            path.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")
            widget = PlotCommonEditorWidget()
            widget.load_path(path)
            self.assertEqual(widget.gap_table.rowCount(), 2)
            rows = widget.gap_rows()
            self.assertEqual({row.scope for row in rows}, {"module", "point"})
            effective = [
                widget.gap_table.item(index, 5).text()
                for index in range(widget.gap_table.rowCount())
            ]
            self.assertTrue(any("连续连接" in text and "测点设置" in text for text in effective))
            self.assertEqual(
                widget.session.build_payload(widget.rows(), rows), payload
            )
            module_combo = widget.gap_table.cellWidget(0, 1)
            module_choices = {
                module_combo.itemText(index)
                for index in range(module_combo.count())
            }
            self.assertIn("动应变（高通）", module_choices)
            self.assertIn("结构加速度频谱趋势", module_choices)
            point_index = next(
                index for index, row in enumerate(rows) if row.scope == "point"
            )
            widget.gap_table.item(point_index, 4).setText("9")
            self.app.processEvents()
            self.assertIn("倍数 9", widget.gap_table.item(point_index, 5).text())
            self.assertEqual(
                widget.gap_rows()[point_index].gap_break_factor, 9
            )

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

    def test_hongtang_peak_band_cells_hide_float_noise(self) -> None:
        widget = SpectrumConfigEditorWidget()
        widget.load_path(ROOT / "config" / "hongtang_config.json")
        matching_rows = [
            index
            for index in range(widget.order_table.rowCount())
            if widget.order_table.item(index, 2).text() == "A10-Y"
            and widget.order_table.item(index, 3).text() == "2"
        ]
        self.assertEqual(len(matching_rows), 1)
        row = matching_rows[0]
        self.assertEqual(widget.order_table.item(row, 6).text(), "1.428")
        self.assertEqual(widget.order_table.item(row, 7).text(), "1.686")

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
