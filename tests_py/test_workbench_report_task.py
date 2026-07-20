from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import unittest
from contextlib import ExitStack
from pathlib import Path
from unittest.mock import patch

from pypdf import PdfWriter

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "reporting"))

from tests_py.locked_docx_media_test_utils import create_minimal_docx
from report_job import (
    REPORT_TYPE_NAMES,
    ReportJobRequest,
    _broken_reference_hits,
    _report_manifest_snapshot,
    _select_new_report_build_manifest,
    build_qc,
    execute_report_job,
)
from report_job_cli import request_from_context
from analysis_manifest import active_pinned_analysis_manifest
from workbench.models import JobContext, file_sha256
from workbench.profiles import load_profiles
from workbench.report_task import read_report_status, report_job_command
from workbench.embedded_report import report_runtime_contract
from word_pdf_export import WordPdfExportResult


class WorkbenchReportTaskTests(unittest.TestCase):
    @staticmethod
    def _write_valid_pdf(path: Path) -> Path:
        writer = PdfWriter()
        writer.add_blank_page(width=612, height=792)
        with path.open("wb") as stream:
            writer.write(stream)
        return path

    def test_broken_reference_gate_detects_word_and_english_results(self) -> None:
        self.assertEqual(_broken_reference_hits("表 错误: 引用源未找到-13"), ["引用源未找到"])
        self.assertEqual(
            _broken_reference_hits("Error! Reference source not found."),
            ["Error! Reference source not found"],
        )

    def _write_closed_manifest(
        self,
        root: Path,
        data_root: Path,
        *,
        bridge_id: str = "guanbing",
        module: str = "temperature",
        config_path: Path | None = None,
    ) -> Path:
        provenance = root / f"{module}.plot.json"
        provenance_payload = json.loads(
            (ROOT / "tests" / "fixtures" / "workbench_provenance_contract.json").read_text(
                encoding="utf-8"
            )
        )
        source = provenance_payload["series"][0]["source"]
        source.update({
            "complete_day_count": 2,
            "incomplete_day_count": 0,
            "incomplete_days": [],
            "missing_required_sources": [],
        })
        provenance.write_text(json.dumps(provenance_payload), encoding="utf-8")
        manifest = root / "analysis_manifest.json"
        manifest.write_text(json.dumps({
            "status": "ok",
            "bridge_profile": {"bridge_id": bridge_id},
            "run_request": {
                "data_root": str(data_root),
                "start_date": "2026-04-01",
                "end_date": "2026-04-30",
                "config_path": str(config_path.resolve()) if config_path else "",
                "config_sha256": file_sha256(config_path) if config_path else "",
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
            command = report_job_command(root, root / "job.json", root / "status.json", root / "result.json")
            self.assertTrue(command[0].endswith("python.exe"))
            self.assertEqual(command[1:3], ("-m", "workbench"))
            self.assertIn("--run-report-job", command)
            self.assertIn("--report-status", command)
            self.assertIn("--report-result", command)
            self.assertNotIn("report_gui.py", command)
            self.assertFalse(any("BridgeReportBuilder" in value for value in command))

    def test_frozen_command_reuses_workbench_executable(self) -> None:
        with tempfile.TemporaryDirectory() as folder, patch(
            "workbench.report_task.sys.frozen", True, create=True
        ), patch("workbench.report_task.sys.executable", r"C:\\app\\bridge.exe"):
            root = Path(folder)
            command = report_job_command(
                root, root / "job.json", root / "status.json", root / "result.json"
            )
            self.assertEqual(command[0], r"C:\\app\\bridge.exe")
            self.assertEqual(command[1], "--run-report-job")
            self.assertFalse(any("BridgeReportBuilder" in value for value in command))

    def test_embedded_runtime_has_no_standalone_window(self) -> None:
        contract = report_runtime_contract()
        self.assertTrue(contract["ok"])
        self.assertEqual(contract["runtime"], "embedded_headless_worker")
        self.assertFalse(contract["standalone_report_window"])
        self.assertEqual(contract["report_type_count"], len(REPORT_TYPE_NAMES))

    def test_embedded_runtime_smoke_runs_worker_and_real_docx_build(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            output = Path(folder) / "runtime_smoke.json"
            completed = subprocess.run(
                [
                    sys.executable,
                    "-m",
                    "workbench",
                    "--report-runtime-smoke-test",
                    "--smoke-output",
                    str(output),
                ],
                cwd=ROOT,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=90,
                check=False,
            )
            self.assertEqual(completed.returncode, 0, completed.stderr)
            payload = json.loads(output.read_text(encoding="utf-8-sig"))
            self.assertTrue(payload["embedded_report_job"])
            self.assertTrue(payload["report_gate_contract"])
            self.assertTrue(payload["visual_qc_contract"])

    def test_source_report_gate_contract_smoke_runs_from_unified_workbench(self) -> None:
        environment = dict(os.environ)
        environment.setdefault("QT_QPA_PLATFORM", "offscreen")
        completed = subprocess.run(
            [sys.executable, "-m", "workbench", "--report-runtime-smoke-test"],
            cwd=ROOT,
            env=environment,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
            check=False,
        )
        self.assertEqual(completed.returncode, 0, completed.stderr)

    def test_retired_report_window_refuses_default_launch(self) -> None:
        environment = dict(os.environ)
        environment.setdefault("QT_QPA_PLATFORM", "offscreen")
        completed = subprocess.run(
            [sys.executable, str(ROOT / "reporting" / "report_gui.py")],
            cwd=ROOT,
            env=environment,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
            check=False,
        )
        self.assertNotEqual(completed.returncode, 0)
        self.assertIn("retired", (completed.stdout + completed.stderr).lower())

    def test_context_request_requires_approval_and_pinned_files(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            data = root / "data"
            data.mkdir()
            config = root / "config.json"
            template = root / "template.docx"
            config.write_text("{}", encoding="utf-8")
            template.write_bytes(b"template")
            manifest = self._write_closed_manifest(root, data, config_path=config)
            context = JobContext.create(
                project_root=ROOT,
                bridge_id="guanbing", bridge_name="管柄大桥", data_root=data,
                start_date="2026-04-01", end_date="2026-04-30", config_path=config,
                selected_modules=["temperature"],
                options={"source_quality_note": "  审定的数据完整性说明。  "},
                report_type="guanbing_monthly",
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
            self.assertEqual(request.source_quality_note, "审定的数据完整性说明。")
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
            manifest = self._write_closed_manifest(root, data, config_path=config)
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
                    "config_path": str(config.resolve()), "config_sha256": file_sha256(config),
                },
                "module_results": [{"key": "temperature", "status": "ok", "artifacts": []}],
            }), encoding="utf-8")
            context.selected_modules = ["temperature"]
            context.analysis.manifest_sha256 = file_sha256(manifest)
            context.write(path)
            with self.assertRaisesRegex(RuntimeError, "没有正式图件的数据核验记录"):
                request_from_context(path)

    def test_strict_gate_uses_composite_top_level_bridge_profile(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            data = root / "data"
            data.mkdir()
            config = root / "config.json"
            template = root / "template.docx"
            config.write_text("{}", encoding="utf-8")
            template.write_bytes(b"template")
            manifest = self._write_closed_manifest(
                root,
                data,
                bridge_id="jiulongjiang",
                module="temperature",
                config_path=config,
            )
            payload = json.loads(manifest.read_text(encoding="utf-8"))
            payload["manifest_type"] = "composite_analysis_recovery"
            payload["run_request"]["bridge_profile"] = {"bridge_id": "stale_source_profile"}
            manifest.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")

            context = JobContext.create(
                project_root=ROOT,
                bridge_id="jiulongjiang",
                bridge_name="九龙江大桥",
                data_root=data,
                start_date="2026-04-01",
                end_date="2026-04-30",
                config_path=config,
                selected_modules=["temperature"],
                options={},
                report_type="jlj_monthly",
                template_path=template,
                output_dir=data / "report",
            )
            context.analysis.state = "completed"
            context.analysis.manifest_path = str(manifest)
            context.analysis.manifest_sha256 = file_sha256(manifest)
            context.report.plots_approved = True
            path = context.write(root / "job_context.json")

            request = request_from_context(path)
            self.assertEqual(request.report_type, "jlj_monthly")

            payload["bridge_profile"] = {"bridge_id": "guanbing"}
            manifest.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")
            context.analysis.manifest_sha256 = file_sha256(manifest)
            context.write(path)
            with self.assertRaisesRegex(RuntimeError, "桥梁不一致"):
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
            pdf = self._write_valid_pdf(output / "report.pdf")
            visual = {
                "status": "passed", "page_count": 1, "pages": [],
                "contact_sheet": "contact.png", "renderer": "authoritative_pdf",
                "pdf_authoritative": True, "pdf_path": str(pdf),
            }
            with patch("report_job.build_guanbing_monthly_report", return_value=(report, manifest)), patch(
                "report_job.render_docx_visual_qc", return_value=visual
            ), patch(
                "report_job.export_authoritative_word_pdf",
                return_value=WordPdfExportResult(pdf, "passed", authoritative=True),
            ):
                result = execute_report_job(request, lambda stage, _fraction, _message: stages.append(stage))
            self.assertEqual(result.qc["status"], "passed")
            self.assertEqual(stages, ["preflight", "building", "rendering", "qc", "completed"])
            self.assertEqual(result.qc["docx"]["media_count"], 1)

    def test_real_report_entries_share_authoritative_word_pdf_export(self) -> None:
        cases = (
            ("guanbing_monthly", "report_job.build_guanbing_monthly_report", "docx_manifest"),
            ("zhishan_monthly", "report_job.build_zhishan_monthly_report", "docx_manifest"),
            ("jlj_monthly", "report_job.build_jlj_monthly_report", "docx_only"),
            ("shuixianhua_monthly", "report_job.build_shuixianhua_monthly_report", "docx_pdf"),
            ("hongtang_monthly", "report_job.build_hongtang_monthly_report", "manifest_docx_missing"),
            ("hongtang_period_wim", "report_job.build_period_report", "manifest_docx_missing"),
        )
        for report_type, builder_target, return_kind in cases:
            with self.subTest(report_type=report_type), tempfile.TemporaryDirectory() as folder:
                root = Path(folder)
                template = create_minimal_docx(root / "template.docx")
                config = root / "config.json"
                config.write_text("{}", encoding="utf-8")
                output = root / "output"
                output.mkdir()
                report = create_minimal_docx(output / "report.docx", color="blue")
                manifest = output / "report_build_manifest.json"
                manifest.write_text(
                    json.dumps({"status": "ok", "missing_count": 0, "warnings": []}),
                    encoding="utf-8",
                )
                pdf = self._write_valid_pdf(output / "report.pdf")
                request = ReportJobRequest(
                    report_type, template, config, root, ROOT, output,
                    "2026年4月", "2026年4月1日至2026年4月30日", "2026年5月1日",
                    "2026-04-01", "2026-04-30", wim_root=root / "wim",
                    source_quality_note="审定的数据完整性说明。",
                )
                builder_result = {
                    "docx_manifest": (report, manifest),
                    "docx_only": report,
                    "docx_pdf": (report, None),
                    "manifest_docx_missing": (manifest, report, []),
                }[return_kind]
                export_result = WordPdfExportResult(pdf, "passed", authoritative=True)
                observed: dict[str, Path | None] = {}

                def visual_qc(_report, _output, *, preferred_pdf_path=None):
                    observed["preferred_pdf_path"] = preferred_pdf_path
                    return {
                        "status": "passed",
                        "page_count": 1,
                        "pages": [],
                        "renderer": "authoritative_pdf",
                        "pdf_authoritative": True,
                        "pdf_path": str(pdf),
                    }

                with ExitStack() as stack:
                    builder_mock = stack.enter_context(
                        patch(builder_target, return_value=builder_result)
                    )
                    if report_type in {"jlj_monthly", "shuixianhua_monthly"}:
                        stack.enter_context(
                            patch("report_job._select_new_report_build_manifest", return_value=manifest)
                        )
                    export_mock = stack.enter_context(
                        patch("report_job.export_authoritative_word_pdf", return_value=export_result)
                    )
                    stack.enter_context(
                        patch("report_job.render_docx_visual_qc", side_effect=visual_qc)
                    )
                    result = execute_report_job(request)

                if report_type in {"jlj_monthly", "shuixianhua_monthly", "zhishan_monthly"}:
                    self.assertEqual(
                        builder_mock.call_args.kwargs["source_quality_note"],
                        "审定的数据完整性说明。",
                    )
                if report_type == "shuixianhua_monthly":
                    self.assertIs(builder_mock.call_args.kwargs["update_word"], False)
                if report_type == "jlj_monthly":
                    self.assertIs(builder_mock.call_args.kwargs["update_word"], False)
                export_mock.assert_called_once_with(report.resolve())
                self.assertEqual(observed["preferred_pdf_path"], pdf.resolve())
                self.assertEqual(result.pdf_path, pdf.resolve())
                self.assertTrue(result.qc["pdf"]["authoritative"])
                self.assertEqual(result.qc["status"], "passed")

    def test_shuixianhua_builder_pdf_is_not_exported_twice(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            template = create_minimal_docx(root / "template.docx")
            config = root / "config.json"
            config.write_text("{}", encoding="utf-8")
            output = root / "output"
            output.mkdir()
            report = create_minimal_docx(output / "report.docx", color="blue")
            pdf = self._write_valid_pdf(output / "report.pdf")
            manifest = output / "report_build_manifest.json"
            manifest.write_text(
                json.dumps({"status": "ok", "missing_count": 0, "warnings": []}),
                encoding="utf-8",
            )
            request = ReportJobRequest(
                "shuixianhua_monthly", template, config, root, ROOT, output,
                "2026年4月", "2026年4月1日至2026年4月30日", "2026年5月1日",
                "2026-04-01", "2026-04-30",
            )
            visual = {
                "status": "passed", "page_count": 1, "pages": [],
                "renderer": "authoritative_pdf", "pdf_authoritative": True,
                "pdf_path": str(pdf),
            }
            with patch(
                "report_job.build_shuixianhua_monthly_report", return_value=(report, pdf)
            ) as builder_mock, patch(
                "report_job._select_new_report_build_manifest", return_value=manifest
            ), patch(
                "report_job.export_authoritative_word_pdf"
            ) as export_mock, patch(
                "report_job.render_docx_visual_qc", return_value=visual
            ):
                result = execute_report_job(request)

            export_mock.assert_not_called()
            self.assertIs(builder_mock.call_args.kwargs["update_word"], False)
            self.assertEqual(result.pdf_path, pdf.resolve())
            self.assertEqual(result.qc["pdf"]["export"]["source"], "builder_word_pdf")

    def test_docx_only_builders_bind_manifest_created_by_current_run(self) -> None:
        cases = (
            ("jlj_monthly", "report_job.build_jlj_monthly_report", False),
            ("shuixianhua_monthly", "report_job.build_shuixianhua_monthly_report", True),
        )
        for report_type, builder_target, builder_returns_pdf in cases:
            with self.subTest(report_type=report_type), tempfile.TemporaryDirectory() as folder:
                root = Path(folder)
                template = create_minimal_docx(root / "template.docx")
                config = root / "config.json"
                config.write_text("{}", encoding="utf-8")
                output = root / "output"
                output.mkdir()
                report = create_minimal_docx(output / "current.docx", color="blue")
                stale_report = create_minimal_docx(output / "stale.docx", color="red")
                pdf = self._write_valid_pdf(output / "current.pdf")
                stale_manifest = output / "jlj_report_build_manifest_20991231_235959.json"
                stale_manifest.write_text(
                    json.dumps({
                        "manifest_type": "report_build",
                        "status": "ok",
                        "missing_count": 0,
                        "warnings": [],
                        "output_docx": str(stale_report),
                    }),
                    encoding="utf-8",
                )
                future = 4_102_444_799
                os.utime(stale_manifest, (future, future))
                current_manifest = output / f"{report_type}_report_build_manifest_20260715_120000.json"
                if builder_returns_pdf:
                    # Cover the same-second filename collision too: the
                    # current build may overwrite a manifest path that was
                    # already present in the reused output directory.
                    current_manifest.write_text(
                        json.dumps({
                            "manifest_type": "report_build",
                            "status": "ok",
                            "missing_count": 0,
                            "warnings": [],
                            "output_docx": str(stale_report),
                        }),
                        encoding="utf-8",
                    )

                def builder(**_kwargs):
                    current_manifest.write_text(
                        json.dumps({
                            "manifest_type": "report_build",
                            "status": "ok",
                            "missing_count": 0,
                            "warnings": [],
                            "output_docx": str(report),
                            "output_docx_sha256": file_sha256(report),
                        }),
                        encoding="utf-8",
                    )
                    return (report, pdf) if builder_returns_pdf else report

                request = ReportJobRequest(
                    report_type, template, config, root, ROOT, output,
                    "2026年5月", "2026年5月1日至2026年5月31日", "2026年6月1日",
                    "2026-05-01", "2026-05-31",
                )
                visual = {
                    "status": "passed", "page_count": 1, "pages": [],
                    "renderer": "authoritative_pdf", "pdf_authoritative": True,
                    "pdf_path": str(pdf),
                }
                with patch(builder_target, side_effect=builder), patch(
                    "report_job.export_authoritative_word_pdf",
                    return_value=WordPdfExportResult(pdf, "passed", authoritative=True),
                ), patch("report_job.render_docx_visual_qc", return_value=visual):
                    result = execute_report_job(request)

                self.assertEqual(result.manifest_path, current_manifest.resolve())
                self.assertGreater(stale_manifest.stat().st_mtime_ns, current_manifest.stat().st_mtime_ns)

    def test_current_run_manifest_rejects_wrong_output_sha256(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            output = Path(folder)
            report = create_minimal_docx(output / "current.docx", color="blue")
            before = _report_manifest_snapshot(output)
            manifest = output / "jlj_report_build_manifest_20260715_120000.json"
            manifest.write_text(
                json.dumps({
                    "manifest_type": "report_build",
                    "output_docx": str(report),
                    "output_docx_sha256": "0" * 64,
                }),
                encoding="utf-8",
            )

            with self.assertRaisesRegex(FileNotFoundError, "output SHA-256 mismatch"):
                _select_new_report_build_manifest(output, report, before)

    def test_libreoffice_fallback_remains_preview_only(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            template = create_minimal_docx(root / "template.docx")
            config = root / "config.json"
            config.write_text("{}", encoding="utf-8")
            output = root / "output"
            output.mkdir()
            report = create_minimal_docx(output / "report.docx", color="blue")
            preview = self._write_valid_pdf(output / "libreoffice-preview.pdf")
            manifest = output / "report_build_manifest.json"
            manifest.write_text(
                json.dumps({"status": "ok", "missing_count": 0, "warnings": []}),
                encoding="utf-8",
            )
            request = ReportJobRequest(
                "guanbing_monthly", template, config, root, ROOT, output,
                "2026年4月", "2026年4月1日至2026年4月30日", "2026年5月1日",
                "2026-04-01", "2026-04-30",
            )
            visual = {
                "status": "passed", "page_count": 1, "pages": [],
                "renderer": "libreoffice_preview", "pdf_authoritative": False,
                "pdf_path": str(preview), "preview_pdf_path": str(preview),
            }
            with patch(
                "report_job.build_guanbing_monthly_report", return_value=(report, manifest)
            ), patch(
                "report_job.export_authoritative_word_pdf",
                return_value=WordPdfExportResult(None, "failed", "Word unavailable"),
            ), patch(
                "report_job.render_docx_visual_qc", return_value=visual
            ):
                result = execute_report_job(request)

            self.assertIsNone(result.pdf_path)
            self.assertFalse(result.qc["pdf"]["authoritative"])
            self.assertEqual(result.qc["status"], "warning")
            self.assertEqual(result.qc["visual"]["preview_pdf_path"], str(preview))

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
            pdf = self._write_valid_pdf(output / "report.pdf")

            def strict_builder(**_kwargs):
                binding = active_pinned_analysis_manifest()
                self.assertIsNotNone(binding)
                observed["path"] = str(binding.path)
                observed["sha256"] = binding.sha256
                return report, report_manifest

            visual = {
                "status": "passed", "page_count": 1, "pages": [],
                "contact_sheet": "contact.png", "renderer": "authoritative_pdf",
                "pdf_authoritative": True, "pdf_path": str(pdf),
            }
            with patch("report_job.raise_for_template"), patch(
                "report_job.build_guanbing_monthly_report", side_effect=strict_builder
            ), patch(
                "report_job.render_docx_visual_qc", return_value=visual
            ), patch(
                "report_job.export_authoritative_word_pdf",
                return_value=WordPdfExportResult(pdf, "passed", authoritative=True),
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
            self.assertEqual(qc["manifest"]["missing_items"], [{"label": "missing formal plot"}])
            self.assertEqual(qc["manifest"]["warnings"], ["filesystem fallback attempted"])
            self.assertIn("missing formal plot", qc["manifest"]["message"])
            self.assertIn("filesystem fallback attempted", qc["manifest"]["message"])

    def test_qc_rejects_pdf_with_broken_caption_reference(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            report = create_minimal_docx(root / "report.docx")
            pdf = root / "report.pdf"
            pdf.write_bytes(b"placeholder")
            manifest = root / "report_manifest.json"
            manifest.write_text(
                json.dumps({"status": "ok", "missing_count": 0, "warnings": []}),
                encoding="utf-8",
            )
            visual = {"status": "passed", "page_count": 1, "pages": []}
            with patch(
                "report_job._pdf_qc",
                return_value={
                    "path": str(pdf),
                    "exists": True,
                    "size_bytes": pdf.stat().st_size,
                    "sha256": "TEST",
                    "page_count": 1,
                    "broken_reference": True,
                    "broken_reference_hits": ["引用源未找到"],
                },
            ):
                qc = build_qc(report, manifest, pdf, visual)

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

            with patch("report_job.raise_for_template"), patch(
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
