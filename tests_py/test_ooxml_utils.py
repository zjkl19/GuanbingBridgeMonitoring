import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "reporting"))

from lxml import etree  # noqa: E402

from ooxml_utils import fill_table, rewrite_paragraphs_containing, xml_text  # noqa: E402


W = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
NS = {"w": W}


def parse_xml(text: str):
    return etree.fromstring(text.encode("utf-8"))


class TestOoxmlUtils(unittest.TestCase):
    def test_rewrite_paragraph_preserves_single_text_value(self):
        root = parse_xml(
            f"""
            <w:document xmlns:w="{W}">
              <w:body><w:p><w:r><w:t>old value</w:t></w:r></w:p></w:body>
            </w:document>
            """
        )

        changed = rewrite_paragraphs_containing(root, "old", "new value")

        self.assertEqual(changed, 1)
        paragraph = root.find(".//w:p", NS)
        self.assertEqual(xml_text(paragraph), "new value")

    def test_fill_table_reuses_existing_rows(self):
        root = parse_xml(
            f"""
            <w:tbl xmlns:w="{W}">
              <w:tr><w:tc><w:p><w:r><w:t>h</w:t></w:r></w:p></w:tc></w:tr>
              <w:tr><w:tc><w:p><w:r><w:t>x</w:t></w:r></w:p></w:tc></w:tr>
            </w:tbl>
            """
        )

        fill_table(root, [{"value": "filled"}], lambda _idx, row: [row["value"]])

        cells = root.findall(".//w:tc", NS)
        self.assertEqual(xml_text(cells[1]), "filled")

    def test_fill_table_expands_from_last_template_row(self):
        root = parse_xml(
            f"""
            <w:tbl xmlns:w="{W}">
              <w:tr><w:tc><w:p><w:r><w:t>h</w:t></w:r></w:p></w:tc></w:tr>
              <w:tr><w:tc><w:p><w:r><w:t>template</w:t></w:r></w:p></w:tc></w:tr>
            </w:tbl>
            """
        )

        fill_table(
            root,
            [{"value": "first"}, {"value": "second"}, {"value": "third"}],
            lambda _idx, row: [row["value"]],
        )

        table_rows = root.findall("w:tr", NS)
        self.assertEqual(len(table_rows), 4)
        self.assertEqual(
            [xml_text(row) for row in table_rows[1:]],
            ["first", "second", "third"],
        )


if __name__ == "__main__":
    unittest.main()
