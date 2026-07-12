import sys
import tempfile
import unittest
from datetime import date
from pathlib import Path

from docx import Document
from openpyxl import Workbook

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "reporting"))

from build_monthly_report import (  # noqa: E402
    build_eq_section,
    build_overview_items,
    build_wind_section,
    format_rms_threshold,
    format_rms_value,
    normalize_eq_peak_key,
    replace_wind_speed_caption,
    update_wind_table,
)
from build_period_report import apply_period_maintenance_log  # noqa: E402


class TestHongtangPeriodFollowups(unittest.TestCase):
    def test_eq_section_maps_base_point_id_and_component_to_direction(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            stats = root / "stats"
            assets = root / "assets"
            stats.mkdir()
            assets.mkdir()

            wb = Workbook()
            ws = wb.active
            ws.append(["PointID", "Component", "Peak", "PeakTime"])
            ws.append(["EQ", "X", 0.005, "2026-04-20 06:42:09"])
            ws.append(["EQ", "Y", 0.018, "2026-06-17 03:22:18"])
            ws.append(["EQ", "Z", 0.019, "2026-06-17 01:02:38"])
            wb.save(stats / "eq_stats.xlsx")

            cfg = {
                "points": {"eq": ["EQ-X", "EQ-Y", "EQ-Z"]},
                "per_point": {
                    "eq": {
                        "EQ-X": {"alarm_levels": [0.1]},
                        "EQ-Y": {"alarm_levels": [0.1]},
                        "EQ-Z": {"alarm_levels": [0.1]},
                    }
                },
            }
            section = build_eq_section(cfg, stats, None, root, assets)

            self.assertEqual(normalize_eq_peak_key("EQ", "X"), "EQ-X")
            self.assertAlmostEqual(section["horizontal_peak"], 0.018)
            self.assertAlmostEqual(section["vertical_peak"], 0.019)
            self.assertIn("0.018m/s²", section["summary"])
            self.assertIn("0.019m/s²", section["summary"])

    def test_period_maintenance_log_replaces_table_with_q2_rows(self):
        doc = Document()
        doc.add_paragraph("表 1-2 健康监测系统维护日志表")
        table = doc.add_table(rows=19, cols=3)
        table.cell(0, 0).text = "序号"
        table.cell(0, 1).text = "维护日期"
        table.cell(0, 2).text = "维护类型"
        for idx in range(1, 19):
            table.cell(idx, 0).text = str(idx)
            table.cell(idx, 1).text = f"2026-03-{idx:02d}"
            table.cell(idx, 2).text = "旧记录"

        apply_period_maintenance_log(doc, date(2026, 4, 1), date(2026, 6, 30))

        self.assertEqual(len(table.rows), 16)
        self.assertEqual([cell.text for cell in table.rows[0].cells], ["序号", "维护日期", "维护类型"])
        self.assertEqual(table.cell(1, 1).text, "2026-04-06")
        self.assertIn("基康采集设备", table.cell(2, 2).text)
        self.assertEqual(table.cell(15, 1).text, "2026-06-29")
        self.assertNotIn("旧记录", "\n".join(cell.text for row in table.rows for cell in row.cells))

    def test_overview_uses_accepted_q2_wording(self):
        manifest = {
            "sections": {
                "wim": {"enabled": False},
                "traffic": {},
                "strain": {"enabled": False, "available": False},
                "tilt": {"enabled": False, "available": False},
                "bearing_displacement": {"enabled": False, "available": False},
                "cable_force": {
                    "enabled": True,
                    "available": True,
                    "accel_available": True,
                    "force_available": True,
                    "max_abs": 2.44,
                    "max_rms": 0.37,
                    "min_change": -7.42,
                    "max_change": 1.77,
                },
                "wind": {"enabled": True, "available": True, "max_10min": 5.46},
                "eq": {"enabled": False, "available": False},
            }
        }

        items = build_overview_items(manifest)
        cable_text = items["吊索索力监测"][0]
        wind_text = items["风向风速监测"][0]

        self.assertIn("监测结果表明，吊索加速度", cable_text)
        self.assertIn("370mm/s²（0.370m/s²）", cable_text)
        self.assertIn("1000mm/s²（1.000m/s²）", cable_text)
        self.assertNotIn("1000m/s²", cable_text)
        self.assertIn("变化幅度均在10%以内", cable_text)
        self.assertNotIn("监测结果表明吊索加速度", cable_text)
        self.assertNotIn("与成桥索力相比变化范围在10%以内", cable_text)
        self.assertIn("桥面测点W1的10min平均风速", wind_text)

    def test_rms_format_preserves_mm_per_second_squared_precision(self):
        self.assertEqual(format_rms_value(0.027), "27mm/s²（0.027m/s²）")
        self.assertEqual(format_rms_value(0.453), "453mm/s²（0.453m/s²）")
        self.assertEqual(format_rms_threshold(315), "315mm/s²（0.315m/s²）")
        self.assertEqual(format_rms_threshold(1000), "1000mm/s²（1.000m/s²）")

    def test_wind_section_uses_accepted_spacing_and_caption(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            stats = root / "stats"
            stats.mkdir()

            wb = Workbook()
            ws = wb.active
            ws.append(["PointID", "Mean10minMax", "MeanSpeed", "MaxSpeed"])
            ws.append(["W1", 5.46, 2.28, 9.25])
            wb.save(stats / "wind_stats.xlsx")

            cfg = {"points": {"wind": ["W1"]}}
            section = build_wind_section(cfg, stats, None, root, root / "assets")

            self.assertIn("桥面测点W1的10min平均风速最大值为5.46m/s", section["summary"])
            self.assertEqual(section["speed_caption"], "W1桥面与W2塔顶10min平均风速时程图")

    def test_wind_speed_caption_prefers_v1738_and_falls_back_to_legacy(self):
        accepted = "W1桥面与W2塔顶10min平均风速时程图"

        current_doc = Document()
        current = current_doc.add_paragraph(accepted)
        legacy = current_doc.add_paragraph("图 4-15 桥面 10min 平均风速时程图")
        replace_wind_speed_caption(current_doc, accepted)
        self.assertEqual(current.text, accepted)
        self.assertEqual(legacy.text, "图 4-15 桥面 10min 平均风速时程图")

        legacy_doc = Document()
        legacy_only = legacy_doc.add_paragraph("图 4-15 桥面 10min 平均风速时程图")
        replace_wind_speed_caption(legacy_doc, accepted)
        self.assertEqual(legacy_only.text, accepted)

    def test_wind_section_distinguishes_locations_and_explains_comparison_limit(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            stats = root / "stats"
            stats.mkdir()

            wb = Workbook()
            ws = wb.active
            ws.append(["PointID", "Mean10minMax", "MeanSpeed", "MaxSpeed"])
            ws.append(["W1", 6.4, 2.74, 10.1])
            ws.append(["W2", 4.2, 1.37, 12.0])
            wb.save(stats / "wind_stats.xlsx")

            cfg = {
                "points": {"wind": ["W1", "W2"]},
                "per_point": {
                    "wind": {
                        "W1": {"location": "右幅桥面12号墩附近散索鞍保护罩"},
                        "W2": {"location": "13号主塔塔顶"},
                    }
                },
            }
            section = build_wind_section(cfg, stats, None, root, root / "assets")

            self.assertIn("桥面测点W1的10min平均风速最大值为6.40m/s", section["summary"])
            self.assertIn("塔顶测点W2的10min平均风速最大值为4.20m/s", section["summary"])
            self.assertIn("两者并非同一竖向测风剖面", section["summary"])
            self.assertIn("塔顶/桥面平均风速比约为50.0%", section["summary"])
            self.assertIn("不能按一般大气边界层的高度增风规律作简单对比", section["summary"])
            self.assertIn("不支持直接判定仪器故障或结构异常", section["summary"])
            self.assertEqual(section["deck_max_10min"], 6.4)
            self.assertEqual(section["tower_max_10min"], 4.2)

    def test_wind_table_clears_stale_template_rows_when_point_missing(self):
        doc = Document()
        table = doc.add_table(rows=3, cols=6)
        headers = ["测点", "平均风向", "主导风向", "平均风速", "最大风速", "主要风速等级"]
        for idx, value in enumerate(headers):
            table.cell(0, idx).text = value
        for row_idx, point_id in ((1, "W1"), (2, "W2")):
            table.cell(row_idx, 0).text = point_id
            for col_idx in range(1, 6):
                table.cell(row_idx, col_idx).text = "旧值"

        update_wind_table(
            doc,
            [{
                "PointID": "W1",
                "mean_dir": "270°",
                "dominant_dir": "270°-292.5°",
                "mean_speed": 2.74,
                "max_speed": 10.1,
                "main_grade": "2-4 m/s",
            }],
        )

        self.assertEqual(table.cell(1, 3).text, "2.74")
        self.assertEqual([table.cell(2, idx).text for idx in range(1, 6)], ["", "", "", "", ""])


if __name__ == "__main__":
    unittest.main()
