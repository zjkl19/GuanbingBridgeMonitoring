import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "reporting"))

from docx import Document  # noqa: E402

from report_qc import check_jlj_report, write_report_qc_report  # noqa: E402


class TestReportQc(unittest.TestCase):
    def test_jlj_qc_detects_forbidden_phrase_and_front_summary(self):
        with tempfile.TemporaryDirectory() as tmp:
            docx = Path(tmp) / "report.docx"
            doc = Document()
            cover = doc.add_table(rows=2, cols=2)
            cover.cell(0, 0).text = "委托单位"
            cover.cell(1, 0).text = "监测结果"
            cover.cell(1, 1).text = "建议结合原始数据进一步复核\n（转下页）"
            cont = doc.add_table(rows=1, cols=2)
            cont.cell(0, 0).text = "监测结果"
            cont.cell(0, 1).text = "（续上页）\n后续内容"
            doc.save(docx)

            result = check_jlj_report(docx)

            self.assertEqual(result.summary["front_summary_table_indices"], [0, 1])
            self.assertTrue(any(issue.code == "forbidden-review-phrase" for issue in result.issues))

            txt_path, json_path = write_report_qc_report(result, tmp, timestamp="20260101_000000")
            self.assertTrue(txt_path.exists())
            self.assertTrue(json_path.exists())

    def test_jlj_qc_reports_summary_table_outside_front_block(self):
        with tempfile.TemporaryDirectory() as tmp:
            docx = Path(tmp) / "report.docx"
            doc = Document()
            cover = doc.add_table(rows=2, cols=2)
            cover.cell(0, 0).text = "委托单位"
            cover.cell(1, 0).text = "监测结果"
            cover.cell(1, 1).text = "首页"
            doc.add_table(rows=1, cols=1).cell(0, 0).text = "正文表"
            stale = doc.add_table(rows=1, cols=2)
            stale.cell(0, 0).text = "监测结果"
            stale.cell(0, 1).text = "错位"
            doc.save(docx)

            result = check_jlj_report(docx)

            self.assertTrue(any(issue.code == "summary-table-outside-front-block" for issue in result.issues))


if __name__ == "__main__":
    unittest.main()
