from __future__ import annotations

import hashlib
import json
import sys
import unittest
import zipfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
REPORTING = ROOT / "reporting"
if str(REPORTING) not in sys.path:
    sys.path.insert(0, str(REPORTING))

from docx_header_fields import audit_section_footer_pagination_fields  # noqa: E402
from template_precheck import check_template  # noqa: E402


CONTRACT_PATH = ROOT / "config" / "public_release_binary_contract_v1.8.2.json"


class GuanbingTemplateReleaseContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        payload = json.loads(CONTRACT_PATH.read_text(encoding="utf-8-sig"))
        cls.contract = next(
            item
            for item in payload["contracts"]
            if item["path"].endswith("G104线管柄大桥监测月报模板-自动报告.docx")
        )
        cls.template = ROOT / cls.contract["path"]

    def test_real_template_matches_the_locked_current_docx_contract(self) -> None:
        payload = self.template.read_bytes()
        self.assertEqual(
            hashlib.sha256(payload).hexdigest().upper(),
            self.contract["current_sha256"],
        )
        with zipfile.ZipFile(self.template) as archive:
            self.assertIsNone(archive.testzip())
            infos = archive.infolist()
            self.assertEqual(len(infos), self.contract["member_count"])
            self.assertEqual(
                sum(info.file_size for info in infos),
                self.contract["current_total_uncompressed_bytes"],
            )
            names = [info.filename for info in infos]
            self.assertEqual(len(names), len(set(names)))
            for name in names:
                self.assertFalse(name.startswith(("/", "\\")), name)
                self.assertNotIn("\\", name)
                self.assertFalse(any(part in {".", ".."} for part in name.split("/")))
                self.assertFalse(archive.getinfo(name).flag_bits & 1, name)
            changed = self.contract["allowed_changed_members"]
            self.assertEqual([item["path"] for item in changed], ["word/footer5.xml"])
            self.assertEqual(
                hashlib.sha256(archive.read("word/footer5.xml")).hexdigest().upper(),
                changed[0]["current_sha256"],
            )

    def test_real_template_footer_fields_and_precheck_are_valid(self) -> None:
        audit = audit_section_footer_pagination_fields(self.template)
        self.assertTrue(audit.valid, (audit.details, audit.formatting_errors))
        self.assertEqual(audit.footer_parts, 1)
        self.assertEqual(audit.pagination_paragraphs, 2)
        self.assertEqual(audit.page_fields, 2)
        self.assertEqual(audit.sectionpages_fields, 2)
        self.assertEqual(audit.static_total_paragraphs, 0)
        self.assertEqual(audit.formatting_errors, ())
        self.assertEqual(check_template("guanbing_monthly", self.template), [])


if __name__ == "__main__":
    unittest.main()
