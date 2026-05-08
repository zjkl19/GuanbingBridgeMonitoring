import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "reporting"))

from docx import Document  # noqa: E402

from docx_table_utils import (  # noqa: E402
    find_first_row_index_by_first_cell,
    find_summary_table,
    normalize_cell_text,
)
from build_jlj_monthly_report import SectionContent  # noqa: E402
from jlj_summary import update_summary_table  # noqa: E402


class TestDocxTableUtils(unittest.TestCase):
    def test_find_summary_table_uses_left_column_labels(self):
        doc = Document()
        doc.add_table(rows=1, cols=1).cell(0, 0).text = "普通表格"
        summary = doc.add_table(rows=2, cols=2)
        summary.cell(0, 0).text = "监测结果"
        summary.cell(0, 1).text = "旧内容"
        summary.cell(1, 0).text = "建  议"
        summary.cell(1, 1).text = "旧建议"

        found = find_summary_table(doc)
        self.assertIsNotNone(found)
        self.assertEqual(found.cell(0, 0).text, summary.cell(0, 0).text)
        self.assertEqual(find_first_row_index_by_first_cell(summary, "建议"), 1)
        self.assertEqual(normalize_cell_text("建  议"), "建议")

    def test_jlj_summary_update_does_not_depend_on_table_index(self):
        doc = Document()
        doc.add_table(rows=1, cols=1).cell(0, 0).text = "封面表"
        summary = doc.add_table(rows=2, cols=2)
        summary.cell(0, 0).text = "监测结果"
        summary.cell(0, 1).text = "旧监测结果"
        summary.cell(1, 0).text = "建  议"
        summary.cell(1, 1).text = "旧建议"
        doc.add_table(rows=1, cols=1).cell(0, 0).text = "后续表"

        keys = [
            "main_env",
            "main_humidity",
            "main_rainfall",
            "main_wind",
            "main_eq",
            "main_traffic",
            "main_deflection",
            "main_bearing",
            "main_gnss",
            "main_vibration",
            "main_strain",
            "main_crack",
            "main_cable",
            "north_strain",
            "north_bearing",
            "north_tilt",
            "south_strain",
            "south_bearing",
            "south_tilt",
        ]
        section_map = {key: SectionContent(narrative="", summary_sentence=f"{key} summary") for key in keys}

        update_summary_table(doc, section_map, "data summary")

        self.assertEqual(len(summary.rows), 2)
        self.assertEqual(summary.cell(0, 0).text.strip(), "监测结果")
        self.assertIn("一、监测系统运行情况", summary.cell(0, 1).text)
        self.assertIn("二、本月监测数据情况", summary.cell(0, 1).text)
        self.assertIn("三、监测数据分析结果", summary.cell(0, 1).text)
        self.assertIn("main_env summary", summary.cell(0, 1).text)
        self.assertEqual(doc.tables[0].cell(0, 0).text, "封面表")
        self.assertEqual(doc.tables[2].cell(0, 0).text, "后续表")


if __name__ == "__main__":
    unittest.main()
