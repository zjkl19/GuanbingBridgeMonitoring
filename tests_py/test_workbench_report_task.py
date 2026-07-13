from __future__ import annotations

import json
import os
import subprocess
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
from analysis_manifest import active_pinned_analysis_manifest
from workbench.models import JobContext, file_sha256
from workbench.profiles import load_profiles
from workbench.report_task import read_report_status, report_job_command


class WorkbenchReportTaskTests(unittest.TestCase):
    def _write_closed_manifest(
        self,
        root: Path,
        data_root: Path,
        *,
        bridge_id: str = "guanbing",
        module: str = "temperature",
    ) -> Path:
        provenance = root / f"{module}.plot.json"
        provenance.write_bytes((ROOT / "tests" / "fixtures" / "workbench_provenance_contract.json").read_bytes())
        manifest = root / "analysis_manifest.json"
        manifest.write_text(json.dumps({
            "status": "ok",
            "bridge_profile": {"bridge_id": bridge_id},
            "run_request": {
                "data_root": str(data_root),
                "start_date": "2026-04-01",
                "end_date": "2026-04-30",
            },
            "module_results": [{
                "key": module,
                "status": "ok",
                "artifacts": [{"kind": "plot_provenance", "path": str(provenance)}],
            }],
        }, ensure_ascii=False), encoding="utf-8")
        return manifest

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

    def test_source_report_gate_contract_smoke_runs_from_reporting_script(self) -> None:
        environment = dict(os.environ)
        environment.setdefault("QT_QPA_PLATFORM", "offscreen")
        completed = subprocess.run(
            [sys.executable, str(ROOT / "reporting" / "report_gui.py"), "--report-gate-contract-smoke-test"],
            cwd=ROOT,
            env=environment,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
            check=False,
        )
        self.assertEqual(completed.returncode, 0, completed.stderr)

    def test_context_request_requires_approval_and_pinned_files(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            data = root / "data"
            data.mkdir()
            config = root / "config.json"
            template = root / "template.docx"
            config.write_text("{}", encoding="utf-8")
            template.write_bytes(b"template")
            manifest = self._write_closed_manifest(root, data)
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
            derived_manifest = root / "derived_artifacts.json"
            derived_manifest.write_text("{}", encoding="utf-8")
            context.report.derived_artifact_manifest_path = str(derived_manifest)
            context.report.derived_artifact_manifest_sha256 = file_sha256(derived_manifest)
            context.report.plots_approved = True
            path = context.write(root / "job_context.json")
            request = request_from_context(path)
            self.assertEqual(request.report_type, "guanbing_monthly")
            self.assertEqual(request.template, template.resolve())
            self.assertEqual(request.analysis_manifest_path, manifest.resolve())
            self.assertEqual(request.analysis_manifest_sha256, file_sha256(manifest))
            self.assertEqual(request.derived_artifact_manifest_path, derived_manifest.resolve())
            self.assertEqual(
                request.derived_artifact_manifest_sha256,
                file_sha256(derived_manifest),
            )
            self.assertTrue(request.require_source_provenance)
            context.report.plots_approved = False
            context.write(path)
            with self.assertRaisesRegex(RuntimeError, "图件尚未审核"):
                request_from_context(path)

    def test_child_process_rechecks_manifest_context_module_and_provenance(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            data = root / "data"
            data.mkdir()
            config = root / "config.json"
            template = root / "template.docx"
            config.write_text("{}", encoding="utf-8")
            template.write_bytes(b"template")
            manifest = self._write_closed_manifest(root, data)
            context = JobContext.create(
                project_root=ROOT,
                bridge_id="guanbing", bridge_name="guanbing", data_root=data,
                start_date="2026-04-01", end_date="2026-04-30", config_path=config,
                selected_modules=["temperature"], options={}, report_type="guanbing_monthly",
                template_path=template, output_dir=data / "report",
            )
            context.analysis.state = "completed"
            context.analysis.manifest_path = str(manifest)
            context.analysis.manifest_sha256 = file_sha256(manifest)
            context.report.plots_approved = True
            path = context.write(root / "job_context.json")
            self.assertEqual(request_from_context(path).result_root, data.resolve())

            context.bridge_id = "hongtang"
            context.write(path)
            with self.assertRaisesRegex(RuntimeError, "桥梁不一致"):
                request_from_context(path)
            context.bridge_id = "guanbing"
            context.selected_modules = ["acceleration"]
            context.write(path)
            with self.assertRaisesRegex(RuntimeError, "未覆盖所选项目"):
                request_from_context(path)

            manifest.write_text(json.dumps({
                "status": "ok",
                "bridge_profile": {"bridge_id": "guanbing"},
                "run_request": {
                    "data_root": str(data), "start_date": "2026-04-01", "end_date": "2026-04-30",
                },
                "module_results": [{"key": "temperature", "status": "ok", "artifacts": []}],
            }), encoding="utf-8")
            context.selected_modules = ["temperature"]
            context.analysis.manifest_sha256 = file_sha256(manifest)
            context.write(path)
            with self.assertRaisesRegex(RuntimeError, "没有正式图件的数据核验记录"):
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
            visual = {"status": "passed", "page_count": 1, "pages": [], "contact_sheet": "contact.png"}
            with patch("report_job.build_guanbing_monthly_report", return_value=(report, manifest)), patch(
                "report_job.render_docx_visual_qc", return_value=visual
            ):
                result = execute_report_job(request, lambda stage, _fraction, _message: stages.append(stage))
            self.assertEqual(result.qc["status"], "passed")
            self.assertEqual(stages, ["preflight", "building", "rendering", "qc", "completed"])
            self.assertEqual(result.qc["docx"]["media_count"], 1)

    def test_execute_job_binds_exact_manifest_for_strict_builder_scope(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            template = create_minimal_docx(root / "template.docx")
            config = root / "config.json"
            config.write_text("{}", encoding="utf-8")
            output = root / "output"
            output.mkdir()
            report = create_minimal_docx(output / "report.docx", color="blue")
            report_manifest = output / "report_build_manifest_1.json"
            report_manifest.write_text(
                json.dumps({"status": "ok", "missing_count": 0, "warnings": []}),
                encoding="utf-8",
            )
            analysis_manifest = root / "analysis_manifest.json"
            analysis_manifest.write_text(json.dumps({"status": "ok"}), encoding="utf-8")
            analysis_hash = file_sha256(analysis_manifest)
            request = ReportJobRequest(
                "guanbing_monthly", template, config, root, ROOT, output,
                "2026年4月", "2026年4月1日至2026年4月30日", "2026年5月1日",
                "2026-04-01", "2026-04-30",
                analysis_manifest_path=analysis_manifest,
                analysis_manifest_sha256=analysis_hash,
                require_source_provenance=True,
            )
            observed: dict[str, str] = {}

            def strict_builder(**_kwargs):
                binding = active_pinned_analysis_manifest()
                self.assertIsNotNone(binding)
                observed["path"] = str(binding.path)
                observed["sha256"] = binding.sha256
                return report, report_manifest

            visual = {"status": "passed", "page_count": 1, "pages": [], "contact_sheet": "contact.png"}
            with patch("report_job.build_guanbing_monthly_report", side_effect=strict_builder), patch(
                "report_job.render_docx_visual_qc", return_value=visual
            ):
                execute_report_job(request)

            self.assertEqual(observed["path"], str(analysis_manifest.resolve()))
            self.assertEqual(observed["sha256"], analysis_hash)
            self.assertIsNone(active_pinned_analysis_manifest())

    def test_strict_qc_rejects_warning_manifest_with_missing_items(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            report = create_minimal_docx(root / "report.docx")
            manifest = root / "report_manifest.json"
            manifest.write_text(json.dumps({
                "status": "warning",
                "missing_count": 1,
                "missing_items": [{"label": "missing formal plot"}],
                "warnings": ["filesystem fallback attempted"],
            }), encoding="utf-8")
            visual = {"status": "passed", "page_count": 1, "pages": []}

            qc = build_qc(
                report,
                manifest,
                None,
                visual,
                require_source_provenance=True,
            )

            self.assertEqual(qc["status"], "failed")

    def test_strict_job_rejects_missing_real_report_manifest(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            template = create_minimal_docx(root / "template.docx")
            config = root / "config.json"
            config.write_text("{}", encoding="utf-8")
            output = root / "output"
            output.mkdir()
            report = create_minimal_docx(output / "report.docx")
            analysis = root / "analysis.json"
            analysis.write_text('{"status":"ok"}', encoding="utf-8")
            request = ReportJobRequest(
                "guanbing_monthly", template, config, root, ROOT, output,
                "2026-04", "2026-04-01 to 2026-04-30", "2026-05-01",
                "2026-04-01", "2026-04-30",
                analysis_manifest_path=analysis,
                analysis_manifest_sha256=file_sha256(analysis),
                require_source_provenance=True,
            )
            visual = {"status": "passed", "page_count": 1, "pages": []}

            with patch(
                "report_job.build_guanbing_monthly_report", return_value=(report, None)
            ), patch("report_job.render_docx_visual_qc", return_value=visual):
                with self.assertRaisesRegex(FileNotFoundError, "real report build manifest"):
                    execute_report_job(request)

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
