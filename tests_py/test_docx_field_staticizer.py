from __future__ import annotations

import unittest
from xml.etree import ElementTree as ET

from reporting.docx_field_staticizer import W_NS, qn, staticize_reference_fields_xml


class DocxFieldStaticizerTests(unittest.TestCase):
    def test_staticizes_styleref_and_ref_but_keeps_seq_and_page(self) -> None:
        xml = f'''<?xml version="1.0" encoding="utf-8"?>
        <w:document xmlns:w="{W_NS}"><w:body><w:p>
          <w:r><w:fldChar w:fldCharType="begin"/></w:r>
          <w:r><w:instrText> STYLEREF 1 \\s </w:instrText></w:r>
          <w:r><w:fldChar w:fldCharType="separate"/></w:r>
          <w:r><w:t>4</w:t></w:r>
          <w:r><w:fldChar w:fldCharType="end"/></w:r>
          <w:r><w:t>-</w:t></w:r>
          <w:r><w:fldChar w:fldCharType="begin"/></w:r>
          <w:r><w:instrText> SEQ 图 \\* ARABIC \\s 1 </w:instrText></w:r>
          <w:r><w:fldChar w:fldCharType="separate"/></w:r>
          <w:r><w:t>13</w:t></w:r>
          <w:r><w:fldChar w:fldCharType="end"/></w:r>
          <w:r><w:fldChar w:fldCharType="begin"/></w:r>
          <w:r><w:instrText> REF _Ref123 \\h </w:instrText></w:r>
          <w:r><w:fldChar w:fldCharType="separate"/></w:r>
          <w:r><w:t>图 2-15</w:t></w:r>
          <w:r><w:fldChar w:fldCharType="end"/></w:r>
        </w:p></w:body></w:document>'''.encode()

        patched, audit = staticize_reference_fields_xml(xml)
        root = ET.fromstring(patched)
        text = "".join(node.text or "" for node in root.iter(qn("t")))
        instructions = "".join(node.text or "" for node in root.iter(qn("instrText")))

        self.assertEqual(audit["complex_field_count"], 2)
        self.assertEqual(text, "4-13图 2-15")
        self.assertNotIn("STYLEREF", instructions)
        self.assertNotIn(" REF ", instructions)
        self.assertIn("SEQ 图", instructions)

    def test_staticizes_nested_styleref_inside_ref_result(self) -> None:
        xml = f'''<?xml version="1.0" encoding="utf-8"?>
        <w:document xmlns:w="{W_NS}"><w:body><w:p>
          <w:r><w:fldChar w:fldCharType="begin"/></w:r>
          <w:r><w:instrText> REF _Ref123 \\h </w:instrText></w:r>
          <w:r><w:fldChar w:fldCharType="separate"/></w:r>
          <w:r><w:t>图 </w:t></w:r>
          <w:r><w:fldChar w:fldCharType="begin"/></w:r>
          <w:r><w:instrText> STYLEREF 1 \\s </w:instrText></w:r>
          <w:r><w:fldChar w:fldCharType="separate"/></w:r>
          <w:r><w:t>2</w:t></w:r>
          <w:r><w:fldChar w:fldCharType="end"/></w:r>
          <w:r><w:t>-15</w:t></w:r>
          <w:r><w:fldChar w:fldCharType="end"/></w:r>
        </w:p></w:body></w:document>'''.encode()

        patched, audit = staticize_reference_fields_xml(xml)
        root = ET.fromstring(patched)
        text = "".join(node.text or "" for node in root.iter(qn("t")))
        instructions = "".join(node.text or "" for node in root.iter(qn("instrText")))

        self.assertEqual(audit["complex_field_count"], 2)
        self.assertEqual(text, "图 2-15")
        self.assertNotIn("REF", instructions)


if __name__ == "__main__":
    unittest.main()
