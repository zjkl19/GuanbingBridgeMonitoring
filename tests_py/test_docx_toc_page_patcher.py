from __future__ import annotations

import unittest
from xml.etree import ElementTree as ET

from reporting.docx_toc_page_patcher import W_NS, _patch_pageref_in_parent, qn, toc_prefix


class DocxTocPagePatcherTests(unittest.TestCase):
    def test_extracts_prefix_and_replaces_pageref_result(self) -> None:
        paragraph = ET.fromstring(f'''<w:p xmlns:w="{W_NS}">
          <w:pPr><w:pStyle w:val="TOC2"/></w:pPr>
          <w:r><w:t>4.7 风向风速监测</w:t></w:r>
          <w:r><w:fldChar w:fldCharType="begin"/></w:r>
          <w:r><w:instrText> PAGEREF _Toc1 \\h </w:instrText></w:r>
          <w:r><w:fldChar w:fldCharType="separate"/></w:r>
          <w:r><w:t>72</w:t></w:r>
          <w:r><w:fldChar w:fldCharType="end"/></w:r>
        </w:p>''')

        self.assertEqual(toc_prefix(paragraph), "4.7")
        self.assertEqual(_patch_pageref_in_parent(paragraph, 101), 1)
        text = "".join(node.text or "" for node in paragraph.iter(qn("t")))
        self.assertEqual(text, "4.7 风向风速监测101")


if __name__ == "__main__":
    unittest.main()
