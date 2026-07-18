from __future__ import annotations

import json
import hashlib
import os
import sys
import tempfile
import unittest
from pathlib import Path

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

ROOT = Path(__file__).resolve().parents[1]
REPORTING = ROOT / "reporting"
if str(REPORTING) not in sys.path:
    sys.path.insert(0, str(REPORTING))

try:
    from PySide6.QtWidgets import QApplication
    from report_gui import ReportGui
    from workbench.models import READABLE_SCHEMA_VERSIONS
except ImportError:  # pragma: no cover
    QApplication = None
    ReportGui = None
    READABLE_SCHEMA_VERSIONS = set()


@unittest.skipIf(QApplication is None, "PySide6/report dependencies are not installed")
class WorkbenchReportContextTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.app = QApplication.instance() or QApplication([])

    def test_report_gui_prefills_approved_workbench_context(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            data = root / "data"
            output = root / "output"
            data.mkdir()
            config = ROOT / "config" / "default_config.json"
            manifest = root / "manifest.json"
            manifest.write_text("{}", encoding="utf-8")
            template = root / "template.docx"
            template.write_bytes(b"test template")
            sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest().upper()
            payload = {
                "schema_version": 1,
                "bridge_id": "guanbing",
                "project_root": str(ROOT),
                "data_root": str(data),
                "config_path": str(config),
                "config_sha256": sha(config),
                "start_date": "2026-03-26",
                "end_date": "2026-04-26",
                "period_label": "2026年4月",
                "monitoring_range": "2026年3月26日至2026年4月26日",
                "report_date": "2026年5月10日",
                "analysis": {"manifest_path": str(manifest), "manifest_sha256": sha(manifest)},
                "report": {
                    "template_path": str(template),
                    "template_sha256": sha(template),
                    "output_dir": str(output),
                    "plots_approved": True,
                },
            }
            context_path = root / "job_context.json"
            context_path.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")
            window = ReportGui(job_context_path=context_path)
            try:
                self.assertEqual(window.profile_combo.currentData(), "guanbing")
                self.assertEqual(window.result_root_edit.text(), str(data))
                self.assertEqual(window.output_dir_edit.text(), str(output))
                self.assertEqual(window.period_edit.text(), "2026年4月")
                self.assertTrue(window.generate_btn.isEnabled())
            finally:
                window.close()

    def test_report_gui_accepts_every_model_readable_context_version(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            data = root / "data"
            output = root / "output"
            data.mkdir()
            config = ROOT / "config" / "default_config.json"
            manifest = root / "manifest.json"
            manifest.write_text("{}", encoding="utf-8")
            template = root / "template.docx"
            template.write_bytes(b"test template")
            sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest().upper()
            base_payload = {
                "bridge_id": "guanbing",
                "project_root": str(ROOT),
                "data_root": str(data),
                "config_path": str(config),
                "config_sha256": sha(config),
                "start_date": "2026-03-26",
                "end_date": "2026-04-26",
                "period_label": "2026年4月",
                "monitoring_range": "2026年3月26日至2026年4月26日",
                "report_date": "2026年5月10日",
                "analysis": {
                    "manifest_path": str(manifest),
                    "manifest_sha256": sha(manifest),
                },
                "report": {
                    "template_path": str(template),
                    "template_sha256": sha(template),
                    "output_dir": str(output),
                    "plots_approved": True,
                },
            }
            for schema_version in sorted(READABLE_SCHEMA_VERSIONS):
                with self.subTest(schema_version=schema_version):
                    payload = dict(base_payload, schema_version=schema_version)
                    if schema_version >= 3:
                        payload["options"] = {
                            "doCachePrebuild": True,
                            "cache_source_cleanup": {
                                "enabled": True,
                                "mode": "verified_extracted_csv",
                                "commit_scope": "day",
                                "recovery_policy": "verified_archive",
                                "confirmation": "DELETE_VERIFIED_EXTRACTED_CSV",
                                "confirmed_at": "2026-07-16T01:30:00+08:00",
                            },
                        }
                    context_path = root / f"job_context_v{schema_version}.json"
                    context_path.write_text(
                        json.dumps(payload, ensure_ascii=False), encoding="utf-8"
                    )
                    window = ReportGui(job_context_path=context_path)
                    try:
                        self.assertEqual(window.profile_combo.currentData(), "guanbing")
                        self.assertEqual(window.result_root_edit.text(), str(data))
                        self.assertEqual(window.output_dir_edit.text(), str(output))
                        self.assertTrue(window.generate_btn.isEnabled())
                    finally:
                        window.close()

    def test_report_gui_rejects_context_version_outside_model_readable_set(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            context_path = Path(folder) / "job_context.json"
            context_path.write_text(
                json.dumps({"schema_version": max(READABLE_SCHEMA_VERSIONS) + 1}),
                encoding="utf-8",
            )
            with self.assertRaisesRegex(ValueError, "Unsupported workbench context schema"):
                ReportGui(job_context_path=context_path)

    def test_report_gui_rejects_changed_pinned_manifest(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            data = root / "data"
            data.mkdir()
            config = ROOT / "config" / "default_config.json"
            manifest = root / "manifest.json"
            manifest.write_text("{}", encoding="utf-8")
            template = root / "template.docx"
            template.write_bytes(b"template")
            sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest().upper()
            payload = {
                "schema_version": 1,
                "bridge_id": "guanbing",
                "project_root": str(ROOT),
                "data_root": str(data),
                "config_path": str(config),
                "config_sha256": sha(config),
                "analysis": {"manifest_path": str(manifest), "manifest_sha256": sha(manifest)},
                "report": {
                    "template_path": str(template),
                    "template_sha256": sha(template),
                    "plots_approved": True,
                },
            }
            context_path = root / "job_context.json"
            context_path.write_text(json.dumps(payload), encoding="utf-8")
            manifest.write_text('{"changed":true}', encoding="utf-8")
            with self.assertRaisesRegex(RuntimeError, "analysis manifest changed"):
                ReportGui(job_context_path=context_path)


if __name__ == "__main__":
    unittest.main()
