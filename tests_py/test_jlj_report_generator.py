import shutil
import sys
import unittest
from datetime import date
from pathlib import Path

from docx import Document

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "reporting"))

from build_jlj_monthly_report import (  # noqa: E402
    clean_jlj_report_xml_text,
    collect_jlj_data_acquisition_rows,
    normalize_cover_monitoring_time,
    read_stats_rows,
    update_jlj_warning_threshold_table,
)


class TestJljReportGenerator(unittest.TestCase):
    def setUp(self):
        self.tmp = Path("tmp") / "test_jlj_report_generator"
        shutil.rmtree(self.tmp, ignore_errors=True)
        self.tmp.mkdir(parents=True)

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_cover_monitoring_time_uses_report_month(self):
        self.assertEqual(
            normalize_cover_monitoring_time("2026年3月份", "2026.03.23~2026.03.31"),
            "2026年3月",
        )
        self.assertEqual(
            normalize_cover_monitoring_time("", "2026.03.23~2026.03.31"),
            "2026年3月",
        )

    def test_data_acquisition_includes_pending_expansion_joint_points(self):
        rows = collect_jlj_data_acquisition_rows({}, self.tmp, date(2026, 3, 23), date(2026, 3, 31))
        expansion_rows = [row for row in rows if row["module"] == "伸缩缝位移监测"]

        self.assertEqual(len(expansion_rows), 1)
        row = expansion_rows[0]
        self.assertEqual(row["design_count"], "4")
        self.assertEqual(row["acquired_count"], "0")
        self.assertEqual(row["rate"], "0.0%")
        self.assertEqual(row["date_range"], "/")
        self.assertIn("新版竣工图新增测点SSFWYJ-01~04", row["remarks"])

    def test_warning_threshold_table_fixed_text_and_arch_lower_bound(self):
        doc = Document()
        table = doc.add_table(rows=4, cols=6)
        for col_idx, value in enumerate(["报警类别", "监测项", "报警规则", "统计值", "上限", "下限"]):
            table.cell(0, col_idx).text = value
        table.cell(1, 1).text = "主梁跨中静应变"
        table.cell(1, 2).text = "超过设计值"
        table.cell(2, 1).text = "主拱拱顶静应变"
        table.cell(2, 2).text = "超过设计值"
        table.cell(3, 1).text = "拱桥主拱拱顶位移"
        table.cell(3, 2).text = "超过0.8倍设计值"
        table.cell(3, 5).text = "-57.4mm"

        update_jlj_warning_threshold_table(doc)

        self.assertEqual(table.cell(3, 5).text, "-59.4mm")
        self.assertIn("MPa", table.cell(1, 4).text)
        self.assertIn("με", table.cell(2, 5).text)

    def test_cleanup_normalizes_accepted_report_text_typos(self):
        path = self.tmp / "cleanup.docx"
        doc = Document()
        doc.add_paragraph("10min加速度速度均方根；桥墩沉降°；DYBCQG-24-K16-ZGD-A20。")
        doc.save(path)

        clean_jlj_report_xml_text(path)

        cleaned = "\n".join(p.text for p in Document(path).paragraphs)
        self.assertIn("10min加速度均方根", cleaned)
        self.assertIn("桥墩沉降", cleaned)
        self.assertIn("DYBCGQ-24-K16-ZGD-A20", cleaned)
        self.assertNotIn("DYBCQG", cleaned)

    def test_missing_optional_stats_returns_empty_rows(self):
        rows = read_stats_rows(self.tmp / "stats", "strain_stats.xlsx", self.tmp)
        self.assertEqual(rows, [])


if __name__ == "__main__":
    unittest.main()
