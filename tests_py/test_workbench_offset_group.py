from __future__ import annotations

import copy
import os
import shutil
import tempfile
import unittest
from pathlib import Path

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

from workbench.config_editor import (
    ConfigEditorError,
    ConfigChangedError,
    GroupPlotConfigEditorSession,
    GroupPlotRow,
    OffsetConfigEditorSession,
    OffsetCorrectionRow,
    apply_group_plots,
    apply_offset_corrections,
    extract_offset_corrections,
)

try:
    from PySide6.QtWidgets import QApplication

    from workbench.advanced_config_tab import (
        GroupPlotConfigEditorWidget,
        OffsetCorrectionEditorWidget,
    )
except ImportError:  # pragma: no cover
    QApplication = None
    GroupPlotConfigEditorWidget = None
    OffsetCorrectionEditorWidget = None


ROOT = Path(__file__).resolve().parents[1]
CONFIGS = (
    "default_config.json",
    "hongtang_config.json",
    "jiulongjiang_config.json",
    "shuixianhua_config.json",
    "chongyangxi_config.json",
    "zhishan_config.json",
)


class WorkbenchOffsetConfigTests(unittest.TestCase):
    def test_shared_matlab_contract_fixture_round_trips(self) -> None:
        session = OffsetConfigEditorSession(
            ROOT / "tests" / "fixtures" / "workbench_offset_group_contract.json"
        )
        self.assertEqual(session.build_payload(session.rows), session.payload)
        cf5 = [row for row in session.rows if row.point_key == "CF-5"]
        self.assertEqual([row.mode for row in cf5], ["fixed", "hourly_median"])

    def test_all_bridge_offset_configs_noop_round_trip(self) -> None:
        for name in CONFIGS:
            with self.subTest(name=name):
                session = OffsetConfigEditorSession(ROOT / "config" / name)
                self.assertEqual(session.build_payload(session.rows), session.payload)

    def test_extracts_scalar_structured_and_segmented_offsets(self) -> None:
        session = OffsetConfigEditorSession(ROOT / "config" / "zhishan_config.json")
        rows = session.rows
        self.assertEqual(len(rows), 24)
        self.assertTrue(any(row.scope == "defaults" and row.mode == "daily_median" for row in rows))
        cf5 = [row for row in rows if row.point_key == "CF-5"]
        self.assertEqual([row.mode for row in cf5], ["fixed", "hourly_median"])
        self.assertTrue(all(row.segmented for row in cf5))
        self.assertEqual([row.segment_index for row in cf5], [1, 2])

    def test_offset_edit_preserves_unrelated_fields(self) -> None:
        payload = {
            "defaults": {"strain": {"thresholds": {"min": -2, "max": 2}}},
            "per_point": {
                "strain": {
                    "S_1": {
                        "offset_correction": 2,
                        "alarm_bounds": {"level1": [-1, 1]},
                    }
                }
            },
            "plot_styles": {"strain": {"line_width": 1}},
        }
        rows = extract_offset_corrections(payload)
        changed = [
            OffsetCorrectionRow(
                row.scope,
                row.module_key,
                row.point_key,
                row.mode,
                3,
            )
            for row in rows
        ]
        updated = apply_offset_corrections(payload, changed)
        self.assertEqual(updated["per_point"]["strain"]["S_1"]["offset_correction"], 3)
        self.assertEqual(
            updated["per_point"]["strain"]["S_1"]["alarm_bounds"],
            payload["per_point"]["strain"]["S_1"]["alarm_bounds"],
        )
        self.assertEqual(updated["plot_styles"], payload["plot_styles"])

    def test_segment_validation_rejects_overlap(self) -> None:
        rows = [
            OffsetCorrectionRow(
                "per_point", "cable_accel", "CF-5", "fixed", 1,
                "2026-05-01", "2026-05-31", True, 1,
            ),
            OffsetCorrectionRow(
                "per_point", "cable_accel", "CF-5", "hourly_median", None,
                "2026-05-20", "2026-06-30", True, 2,
            ),
        ]
        with self.assertRaisesRegex(ConfigEditorError, "重叠"):
            apply_offset_corrections({}, rows)

    def test_offset_save_backs_up_and_refuses_external_drift(self) -> None:
        fixture = ROOT / "tests" / "fixtures" / "workbench_offset_group_contract.json"
        with tempfile.TemporaryDirectory() as folder:
            target = Path(folder) / "config.json"
            shutil.copy2(fixture, target)
            session = OffsetConfigEditorSession(target)
            rows = [
                OffsetCorrectionRow(
                    row.scope,
                    row.module_key,
                    row.point_key,
                    row.mode,
                    3 if row.point_key == "S_1" else row.value,
                    row.start_date,
                    row.end_date,
                    row.segmented,
                    row.segment_index,
                    row.note,
                )
                for row in session.rows
            ]
            result = session.save(rows)
            self.assertTrue(result.changed)
            self.assertTrue(result.backup_path and result.backup_path.is_file())

            drifted = OffsetConfigEditorSession(target)
            target.write_text(target.read_text(encoding="utf-8") + "\n", encoding="utf-8")
            with self.assertRaises(ConfigChangedError):
                drifted.save(drifted.rows)


class WorkbenchGroupPlotConfigTests(unittest.TestCase):
    def test_shared_matlab_contract_fixture_round_trips(self) -> None:
        session = GroupPlotConfigEditorSession(
            ROOT / "tests" / "fixtures" / "workbench_offset_group_contract.json"
        )
        drafts = {module: session.rows_for(module) for module in session.modules}
        self.assertEqual(session.build_payload_all(drafts), session.payload)
        self.assertEqual(
            [row.group_key for row in session.rows_for("deflection")], ["G1", "G2"]
        )

    def test_all_bridge_group_modules_noop_round_trip(self) -> None:
        for name in CONFIGS:
            with self.subTest(name=name):
                session = GroupPlotConfigEditorSession(ROOT / "config" / name)
                drafts = {module: session.rows_for(module) for module in session.modules}
                self.assertEqual(session.build_payload_all(drafts), session.payload)

    def test_historical_list_representation_is_preserved(self) -> None:
        payload = {
            "points": {"deflection": ["D1", "D2", "D3"]},
            "groups": {"deflection": [["D1", "D2"], ["D3"]]},
            "plot_styles": {"deflection": {}},
        }
        session_payload = copy.deepcopy(payload)
        rows = [
            GroupPlotRow("deflection", "G1", "", ("D1", "D2")),
            GroupPlotRow("deflection", "G2", "", ("D3",)),
        ]
        self.assertEqual(apply_group_plots(session_payload, "deflection", rows), payload)

    def test_group_edit_preserves_other_modules_and_shared_labels(self) -> None:
        payload = {
            "points": {"strain": ["S1", "S2", "S3"]},
            "groups": {
                "strain": {"BOX": ["S1", "S2"]},
                "strain_timeseries": {"TS": ["S1", "S2"]},
            },
            "plot_styles": {
                "strain": {"group_labels": {"BOX": "箱线", "TS": "时程"}, "line_width": 1}
            },
        }
        rows = [GroupPlotRow("strain_timeseries", "TS", "时程新名", ("S2", "S3"))]
        updated = apply_group_plots(payload, "strain_timeseries", rows)
        self.assertEqual(updated["groups"]["strain"]["BOX"], ["S1", "S2"])
        self.assertEqual(updated["groups"]["strain_timeseries"]["TS"], ["S2", "S3"])
        self.assertEqual(updated["plot_styles"]["strain"]["group_labels"]["BOX"], "箱线")
        self.assertEqual(updated["plot_styles"]["strain"]["group_labels"]["TS"], "时程新名")
        self.assertEqual(updated["plot_styles"]["strain"]["line_width"], 1)

    def test_group_validation_rejects_bad_keys_duplicates_and_unknown_points(self) -> None:
        payload = {
            "points": {"deflection": ["D1", "D2"]},
            "groups": {"deflection": {"G1": ["D1"]}},
        }
        with self.assertRaises(ConfigEditorError):
            apply_group_plots(
                payload,
                "deflection",
                [GroupPlotRow("deflection", "中文-组", "", ("D1",))],
            )
        with self.assertRaisesRegex(ConfigEditorError, "未知测点"):
            apply_group_plots(
                payload,
                "deflection",
                [GroupPlotRow("deflection", "G2", "", ("D404",))],
            )

    def test_shared_strain_labels_must_remain_consistent(self) -> None:
        session = GroupPlotConfigEditorSession(
            ROOT / "tests" / "fixtures" / "workbench_offset_group_contract.json"
        )
        drafts = {module: session.rows_for(module) for module in session.modules}
        drafts["strain_timeseries"] = [
            GroupPlotRow("strain_timeseries", "TS", "冲突名称", ("S-1", "S-2"))
        ]
        drafts["strain"] = [
            GroupPlotRow("strain", "TS", "另一名称", ("S-1", "S-2"))
        ]
        with self.assertRaisesRegex(ConfigEditorError, "共用 group_labels"):
            session.build_payload_all(drafts)


@unittest.skipIf(QApplication is None, "PySide6 is not installed")
class WorkbenchOffsetGroupGuiTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.app = QApplication.instance() or QApplication([])

    def test_offset_widget_loads_real_structured_zhishan_rules(self) -> None:
        widget = OffsetCorrectionEditorWidget()
        widget.load_path(ROOT / "config" / "zhishan_config.json")
        self.assertEqual(widget.table.rowCount(), 24)
        modes = {widget.table.item(row, 3).text() for row in range(widget.table.rowCount())}
        self.assertIn("hourly_median", modes)
        self.assertEqual(widget.rows(), widget.session.rows)

    def test_group_widget_loads_modules_and_preserves_current_draft(self) -> None:
        widget = GroupPlotConfigEditorWidget()
        widget.load_path(ROOT / "config" / "zhishan_config.json")
        modules = {
            str(widget.module_combo.itemData(index))
            for index in range(widget.module_combo.count())
        }
        self.assertIn("strain", modules)
        self.assertIn("strain_timeseries", modules)
        index = widget.module_combo.findData("strain")
        widget.module_combo.setCurrentIndex(index)
        self.assertEqual(widget.group_table.rowCount(), 3)
        self.assertGreater(widget.available_list.count(), 0)
        drafts = widget._draft_payload()
        self.assertEqual(widget.session.build_payload_all(drafts), widget.session.payload)


if __name__ == "__main__":
    unittest.main()
