import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

from docx import Document

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "reporting"))

from calibrate_hongtang_period_template import calibrate_template  # noqa: E402
from docx_header_fields import (  # noqa: E402
    HONGTANG_HEADER_WIDTHS_TWIPS,
    audit_header_pagination_fields,
    ensure_header_pagination_fields,
)


def add_hongtang_header(doc: Document) -> None:
    table = doc.sections[0].header.add_table(rows=1, cols=3, width=1)
    table.cell(0, 0).text = "报告编号：BG02FQJC2600002-J2"
    table.cell(0, 1).text = "福建省建筑工程质量检测中心有限公司"
    table.cell(0, 2).text = "第 1 页 共 76 页第 1 页 共 76 页"


class TestDocxHeaderFields(unittest.TestCase):
    def test_audit_accepts_word_normalized_simple_numpages_field(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            path = Path(temp_dir) / "word-normalized.docx"
            header = (
                '<w:hdr xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
                '<w:p><w:r><w:t>报告编号：BG02FQJC2600002-J2</w:t></w:r></w:p>'
                '<w:p><w:r><w:t xml:space="preserve">第 </w:t></w:r>'
                '<w:r><w:instrText> PAGE </w:instrText></w:r><w:r><w:t>1</w:t></w:r>'
                '<w:r><w:t xml:space="preserve"> 页 共 </w:t></w:r>'
                '<w:fldSimple w:instr=" NUMPAGES "><w:r><w:t>106</w:t></w:r></w:fldSimple>'
                '<w:r><w:t xml:space="preserve"> 页</w:t></w:r></w:p></w:hdr>'
            )
            with zipfile.ZipFile(path, "w") as archive:
                archive.writestr("word/header1.xml", header)

            audit = audit_header_pagination_fields(path)

            self.assertTrue(audit.valid, audit.details)
            self.assertEqual(audit.page_fields, 1)
            self.assertEqual(audit.numpages_fields, 1)

    def test_replaces_duplicate_static_pagination_with_fields(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            path = Path(temp_dir) / "header.docx"
            doc = Document()
            add_hongtang_header(doc)

            self.assertEqual(ensure_header_pagination_fields(doc), 1)
            doc.save(path)

            audit = audit_header_pagination_fields(path)
            self.assertTrue(audit.valid, audit.details)
            self.assertEqual(audit.page_fields, 1)
            self.assertEqual(audit.numpages_fields, 1)
            self.assertEqual(audit.duplicate_page_phrases, 0)
            calibrated = Document(path)
            widths = tuple(
                int(cell._tc.tcPr.tcW.w)
                for cell in calibrated.sections[0].header.tables[0].rows[0].cells
            )
            self.assertEqual(widths, HONGTANG_HEADER_WIDTHS_TWIPS)

    def test_template_calibration_applies_proofreading_and_header_contract(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            source = root / "source.docx"
            output = root / "output.docx"
            doc = Document()
            add_hongtang_header(doc)
            doc.add_paragraph("主塔倾斜采用倾角仪实时测量，通过倾角值的变化来反应主塔的倾斜情况。")
            doc.add_paragraph("图 2-12 主梁加速度传感纵断面布置图（单位：m）")
            doc.add_paragraph("监测结果如表4-12所示。监测结果表明，桥面10min平均风速最大值为5.46m/s。")
            doc.save(source)

            result = calibrate_template(source, output)

            self.assertEqual(result["header_cells"], 1)
            calibrated = Document(output)
            text = "\n".join(paragraph.text for paragraph in calibrated.paragraphs)
            self.assertIn("反映主塔的倾斜情况", text)
            self.assertIn("主梁加速度传感器纵断面布置图", text)
            self.assertIn("瞬时最大风速", text)
            self.assertTrue(audit_header_pagination_fields(output).valid)


if __name__ == "__main__":
    unittest.main()
