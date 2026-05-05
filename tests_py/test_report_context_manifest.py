import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "reporting"))

from docx import Document  # noqa: E402

from report_build_manifest import normalize_missing, write_report_build_manifest  # noqa: E402
from report_context import ReportBuildContext  # noqa: E402


class TestReportContextManifest(unittest.TestCase):
    def test_context_defaults_to_result_root_outputs(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            template = root / "template.docx"
            template.write_text("x", encoding="utf-8")

            ctx = ReportBuildContext.from_inputs(template=template, result_root=root, assets_subdir="assets")

            self.assertEqual(ctx.stats_root, root)
            self.assertEqual(ctx.image_root, root)
            self.assertEqual(ctx.output_dir, root / "自动报告")
            self.assertTrue(ctx.assets_dir.exists())
            self.assertEqual(ctx.to_manifest_paths()["result_root"], str(root))

    def test_write_report_build_manifest(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            template = root / "template.docx"
            docx = root / "out.docx"
            Document().save(template)
            Document().save(docx)
            ctx = ReportBuildContext.from_inputs(template=template, result_root=root)

            manifest_path = write_report_build_manifest(
                context=ctx,
                report_type="unit",
                output_docx=docx,
                timestamp="20260505_010203",
                missing=["warning:缺少图片"],
            )

            payload = json.loads(manifest_path.read_text(encoding="utf-8"))
            self.assertEqual(payload["manifest_type"], "report_build")
            self.assertEqual(payload["status"], "warning")
            self.assertEqual(payload["missing_items"][0]["category"], "warning")

    def test_normalize_missing_accepts_dicts_and_strings(self):
        items = normalize_missing([{"item": "A", "detail": "B"}, "missing C"])
        self.assertEqual(items[0]["label"], "A")
        self.assertEqual(items[1]["category"], "missing")


if __name__ == "__main__":
    unittest.main()
