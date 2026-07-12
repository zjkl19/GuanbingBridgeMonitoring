from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "reporting"))

from tests_py.locked_docx_media_test_utils import create_minimal_docx
from report_job import REPORT_TYPE_NAMES, ReportJobRequest, build_qc, execute_report_job
from report_job_cli import request_from_context
from workbench.models import JobContext, file_sha256
from workbench.profiles import load_profiles
from workbench.report_task import read_report_status, report_job_command


class WorkbenchReportTaskTests(unittest.TestCase):
    def test_all_report_capable_profiles_have_embedded_dispatch(self) -> None:
        profiles = load_profiles(ROOT)
        actual = {profile.report_gui_type for profile in profiles if profile.report_gui_type}
        self.assertTrue(actual.issubset(REPORT_TYPE_NAMES))
        self.assertEqual(len(actual), 5)

    def test_source_command_uses_status_and_result_contract(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            reporting = root / "reporting"
            (reporting / ".venv" / "Scripts").mkdir(parents=True)
            (reporting / ".venv" / "Scripts" / "python.exe").write_bytes(b"x")
            (reporting / "report_job_cli.py").write_text("", encoding="utf-8")
            command = report_job_command(root, root / "job.json", root / "status.json", root / "result.json")
            self.assertTrue(command[0].endswith("python.exe"))
            self.assertIn("--status", command)
            self.assertIn("--result", command)

    def test_context_request_requires_approval_and_pinned_files(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            data = root / "data"
            data.mkdir()
            config = root / "config.json"
            template = root / "template.docx"
            manifest = root / "analysis_manifest.json"
            config.write_text("{}", encoding="utf-8")
            template.write_bytes(b"template")
            manifest.write_text("{}", encoding="utf-8")
            context = JobContext.create(
                project_root=ROOT,
                bridge_id="guanbing", bridge_name="管柄大桥", data_root=data,
                start_date="2026-04-01", end_date="2026-04-30", config_path=config,
                selected_modules=["temperature"], options={}, report_type="guanbing_monthly",
                template_path=template, output_dir=data / "自动报告",
            )
            context.analysis.state = "completed"
            context.analysis.manifest_path = str(manifest)
            context.analysis.manifest_sha256 = file_sha256(manifest)
            context.report.plots_approved = True
            path = context.write(root / "job_context.json")
            request = request_from_context(path)
            self.assertEqual(request.report_type, "guanbing_monthly")
            self.assertEqual(request.template, template.resolve())
            context.report.plots_approved = False
            context.write(path)
            with self.assertRaisesRegex(RuntimeError, "not approved"):
                request_from_context(path)

    def test_execute_job_emits_stages_and_structural_qc(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            template = create_minimal_docx(root / "template.docx")
            config = root / "config.json"
            config.write_text("{}", encoding="utf-8")
            output = root / "output"
            output.mkdir()
            report = create_minimal_docx(output / "report.docx", color="blue")
            manifest = output / "report_build_manifest_1.json"
            manifest.write_text(json.dumps({"status": "ok", "missing_count": 0, "warnings": []}), encoding="utf-8")
            request = ReportJobRequest(
                "guanbing_monthly", template, config, root, ROOT, output,
                "2026年4月", "2026年04月01日~2026年04月30日", "2026年05月01日",
                "2026-04-01", "2026-04-30",
            )
            stages: list[str] = []
            with patch("report_job.build_guanbing_monthly_report", return_value=(report, manifest)):
                result = execute_report_job(request, lambda stage, _fraction, _message: stages.append(stage))
            self.assertEqual(result.qc["status"], "passed")
            self.assertEqual(stages, ["preflight", "building", "qc", "completed"])
            self.assertEqual(result.qc["docx"]["media_count"], 1)

    def test_qc_rejects_non_docx_and_status_reader_merges_result(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            broken = root / "broken.docx"
            broken.write_text("not a zip", encoding="utf-8")
            manifest = root / "manifest.json"
            manifest.write_text(json.dumps({"status": "ok"}), encoding="utf-8")
            self.assertEqual(build_qc(broken, manifest, None)["status"], "failed")
            config = root / "config.json"
            config.write_text("{}", encoding="utf-8")
            context = JobContext.create(
                project_root=ROOT, bridge_id="x", bridge_name="x", data_root=root,
                start_date="2026-01-01", end_date="2026-01-01", config_path=config,
                selected_modules=["temperature"], options={},
            )
            status_path = Path(context.report.status_path)
            result_path = Path(context.report.result_path)
            status_path.parent.mkdir(parents=True, exist_ok=True)
            status_path.write_text(json.dumps({"state": "running", "stage": "qc"}), encoding="utf-8")
            result_path.write_text(json.dumps({"state": "completed", "report_path": "done.docx", "qc": {"status": "passed"}}), encoding="utf-8")
            merged = read_report_status(context)
            self.assertEqual(merged["state"], "completed")
            self.assertEqual(merged["stage"], "qc")

    def test_dead_report_process_without_result_becomes_launch_failed(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            config = root / "config.json"
            config.write_text("{}", encoding="utf-8")
            context = JobContext.create(
                project_root=ROOT, bridge_id="x", bridge_name="x", data_root=root,
                start_date="2026-01-01", end_date="2026-01-01", config_path=config,
                selected_modules=["temperature"], options={},
            )
            context.report.state = "launched"
            context.report.pid = 2_000_000_000
            status = read_report_status(context)
            self.assertEqual(status["state"], "launch_failed")
            self.assertEqual(status["stage"], "process_exit")


if __name__ == "__main__":
    unittest.main()
