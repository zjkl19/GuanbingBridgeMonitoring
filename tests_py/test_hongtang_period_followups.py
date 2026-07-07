import sys
import tempfile
import unittest
from datetime import date
from pathlib import Path

from docx import Document
from openpyxl import Workbook

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "reporting"))

from build_monthly_report import build_eq_section, build_overview_items, build_wind_section, normalize_eq_peak_key  # noqa: E402
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
        self.assertIn("变化幅度均在10%以内", cable_text)
        self.assertNotIn("监测结果表明吊索加速度", cable_text)
        self.assertNotIn("与成桥索力相比变化范围在10%以内", cable_text)
        self.assertIn("桥面 10min 平均风速", wind_text)

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

            self.assertIn("桥面 10min 平均风速最大值为5.46m/s", section["summary"])
            self.assertEqual(section["speed_caption"], "桥面 10min 平均风速时程图")


if __name__ == "__main__":
    unittest.main()
