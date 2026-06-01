import json
import sys
import tempfile
import unittest
from pathlib import Path

from openpyxl import Workbook

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "reporting"))

from build_shuixianhua_monthly_report import (  # noqa: E402
    _sxh_accel_rms_limits_mps2,
    _sxh_accel_rms_status,
    _sxh_context,
    scaled_accel_rows,
)
from shuixianhua_table_anchors import required_result_tables  # noqa: E402
from lxml import etree  # noqa: E402


def _write_rows(path: Path, headers: list[str], rows: list[list[object]]) -> None:
    wb = Workbook()
    ws = wb.active
    ws.append(headers)
    for row in rows:
        ws.append(row)
    wb.save(path)


class ShuixianhuaReportGeneratorTest(unittest.TestCase):
    def test_acceleration_rows_convert_cm_s2_to_m_s2(self):
        rows = scaled_accel_rows([
            {"PointID": "ZLZD-01", "Min": -68.3, "Max": 12.5, "Mean": 0, "RMS10minMax": 68.3}
        ])

        self.assertAlmostEqual(rows[0]["Min"], -0.683)
        self.assertAlmostEqual(rows[0]["Max"], 0.125)
        self.assertAlmostEqual(rows[0]["Mean"], 0.0)
        self.assertAlmostEqual(rows[0]["RMS10minMax"], 0.683)

    def test_acceleration_rms_limits_are_read_from_cm_s2_config(self):
        cfg = {
            "groups": {"acceleration": {"ZG": ["ZGZD-01"], "ZL": ["ZLZD-01"]}},
            "plot_styles": {
                "acceleration": {
                    "rms_warn_lines": {
                        "ZG": [{"y": 31.5}, {"y": 50}],
                        "ZL": [{"y": 31.5}, {"y": 50}],
                    }
                }
            },
        }

        first, second = _sxh_accel_rms_limits_mps2(cfg, "ZGZD-01")

        self.assertAlmostEqual(first, 0.315)
        self.assertAlmostEqual(second, 0.5)

    def test_acceleration_rms_status_reports_exceedance(self):
        level1_status = _sxh_accel_rms_status(0.4, 0.315, 0.5)
        level2_status = _sxh_accel_rms_status(0.683, 0.315, 0.5)

        self.assertIn("超过一级阈值0.315m/s²", level1_status)
        self.assertIn("未超过二级阈值0.5m/s²", level1_status)
        self.assertEqual(level2_status, "超过二级阈值0.5m/s²。")

    def test_template_tables_are_found_by_caption(self):
        template = Path(__file__).resolve().parents[1] / "reports" / "水仙花大桥健康监测月报模板.docx"
        with tempfile.TemporaryDirectory() as tmp:
            docx = Path(tmp) / "template.docx"
            docx.write_bytes(template.read_bytes())
            from zipfile import ZipFile

            with ZipFile(docx) as zf:
                root = etree.fromstring(zf.read("word/document.xml"))

        tables = required_result_tables(root)

        self.assertIn("acquisition", tables)
        self.assertIn("strain", tables)
        self.assertIn("cable_accel", tables)

    def test_context_falls_back_to_config_and_stats_when_acquisition_summary_is_absent(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            stats = root / "stats"
            stats.mkdir()
            cfg = {
                "points": {
                    "temperature": ["WD-01", "WSD-01"],
                    "humidity": ["WSD-01"],
                    "wind_speed": ["FSFX-01"],
                    "eq": ["JSD-01"],
                    "deflection": ["GSNDY-01"],
                    "bearing_displacement": ["ZZWY-01"],
                    "acceleration": ["ZLZD-01"],
                    "strain": ["GLYB-01"],
                    "cable_accel": ["SL-01"],
                },
                "design_points_pending": {"gnss": ["GNSS-01"]},
            }
            cfg_path = root / "config.json"
            cfg_path.write_text(json.dumps(cfg, ensure_ascii=False), encoding="utf-8")

            _write_rows(stats / "temp_stats.xlsx", ["PointID", "Min", "Max", "Mean"], [["WSD-01", 20, 30, 25]])
            _write_rows(stats / "humidity_stats.xlsx", ["PointID", "Min", "Max", "Mean"], [["WSD-01", 50, 60, 55]])
            _write_rows(stats / "wind_stats.xlsx", ["PointID", "MeanSpeed", "MaxSpeed", "Mean10minMax"], [["FSFX-01", 1, 2, 1.5]])
            _write_rows(stats / "eq_stats.xlsx", ["PointID", "Component", "Min", "Max"], [["JSD-01", "X", -0.1, 0.1]])
            _write_rows(stats / "deflection_stats.xlsx", ["PointID", "OrigMin_mm", "OrigMax_mm", "FiltMin_mm", "FiltMax_mm"], [["GSNDY-01", -1, 2, -0.5, 1.5]])
            _write_rows(stats / "bearing_displacement_stats.xlsx", ["PointID", "OrigMin_mm", "OrigMax_mm", "FiltMin_mm", "FiltMax_mm"], [["ZZWY-01", -1, 1, -0.8, 0.8]])
            _write_rows(stats / "accel_stats.xlsx", ["PointID", "Min", "Max", "RMS10minMax"], [["ZLZD-01", -0.01, 0.02, 0.01]])
            _write_rows(stats / "strain_stats.xlsx", ["PointID", "Min", "Max", "Mean"], [["GLYB-01", -10, 20, 1]])
            _write_rows(stats / "cable_accel_stats.xlsx", ["PointID", "Min", "Max", "RMS10minMax"], [["SL-01", -0.01, 0.02, 0.01]])

            context = _sxh_context(cfg_path, root, "2026年03月23日~2026年03月31日")

        rows = {row["模块"]: row for row in context["report_rows"]}
        self.assertEqual(rows["温度"]["配置测点数"], 2)
        self.assertEqual(rows["温度"]["实际获取测点数"], 1)
        self.assertEqual(rows["拱顶、拱脚位移（GNSS）"]["缺失说明"], "本月未获取有效数据")


if __name__ == "__main__":
    unittest.main()
