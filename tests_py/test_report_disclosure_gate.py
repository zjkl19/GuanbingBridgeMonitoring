from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

from workbench.models import JobContext, file_sha256
from workbench.report_disclosures import (
    DISCLOSURE_POLICY_VERSION,
    confirmation_record,
)
from workbench.report_gate import inspect_report_gate, require_report_gate


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "reporting"))

from report_job_cli import request_from_job_context  # noqa: E402


class ReportDisclosureGateTests(unittest.TestCase):
    def _context(
        self,
        root: Path,
        *,
        provenance_status: str = "incomplete",
        module_status: str = "ok",
        module_message: str = "",
        report_type: str = "guanbing_monthly",
    ) -> tuple[JobContext, Path]:
        data = root / "data"
        data.mkdir()
        config = root / "config.json"
        config.write_text("{}", encoding="utf-8")
        template = root / "template.docx"
        template.write_bytes(b"template")
        provenance = root / "temperature.plot.json"
        incomplete = provenance_status == "incomplete"
        provenance.write_text(
            json.dumps({
                "series": [{
                    "point_id": "T1",
                    "sampling_mode": "full",
                    "reduction_applied": False,
                    "input_count": 10,
                    "finite_count": 9,
                    "plotted_finite_count": 9,
                    "source": {
                        "source_sample_count": 10,
                        "finite_source_sample_count": 9,
                        "completeness_scope": "required_export_contribution",
                        "internal_gap_coverage_assessed": True,
                        "calendar_day_count_requested": 2,
                        "complete_day_count": 1 if incomplete else 2,
                        "incomplete_day_count": 1 if incomplete else 0,
                        "incomplete_days": ["2026-04-02"] if incomplete else [],
                        "missing_required_sources": ["2026-04-02"] if incomplete else [],
                    },
                }]
            }, ensure_ascii=False),
            encoding="utf-8",
        )
        manifest = root / "analysis_manifest.json"
        artifacts = (
            [{"kind": "plot_provenance", "path": str(provenance)}]
            if module_status == "ok"
            else []
        )
        manifest.write_text(
            json.dumps({
                "status": "ok",
                "bridge_profile": {"bridge_id": "unit"},
                "run_request": {
                    "data_root": str(data),
                    "start_date": "2026-04-01",
                    "end_date": "2026-04-30",
                    "config_path": str(config),
                    "config_sha256": file_sha256(config),
                },
                "module_results": [{
                    "key": "temperature",
                    "label": "温度分析",
                    "status": module_status,
                    "message": module_message,
                    "artifacts": artifacts,
                }],
            }, ensure_ascii=False),
            encoding="utf-8",
        )
        context = JobContext.create(
            project_root=ROOT,
            bridge_id="unit",
            bridge_name="测试桥",
            data_root=data,
            start_date="2026-04-01",
            end_date="2026-04-30",
            config_path=config,
            selected_modules=["temperature"],
            options={},
            report_type=report_type,
            template_path=template,
            output_dir=data / "report",
        )
        context.analysis.state = "completed"
        context.analysis.manifest_path = str(manifest)
        context.analysis.manifest_sha256 = file_sha256(manifest)
        context.report.plots_approved = True
        return context, manifest

    def _confirm_all(self, context: JobContext) -> None:
        audit = inspect_report_gate(context)
        context.report.disclosure_manifest_sha256 = context.analysis.manifest_sha256
        context.report.disclosure_policy_version = DISCLOSURE_POLICY_VERSION
        context.report.disclosure_confirmations = [
            confirmation_record(
                item,
                analysis_manifest_sha256=context.analysis.manifest_sha256,
            )
            for item in audit.disclosure_items
        ]

    def test_incomplete_source_requires_exact_per_item_confirmation(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            context, _ = self._context(Path(folder))
            audit = inspect_report_gate(context)
            self.assertFalse(audit.passed)
            self.assertFalse(audit.hard_issues)
            self.assertEqual(len(audit.disclosure_items), 1)
            self.assertEqual(
                audit.disclosure_items[0].reason_code,
                "incomplete_source_coverage",
            )

            self._confirm_all(context)
            accepted = require_report_gate(context)
            self.assertTrue(accepted.passed)
            self.assertEqual(len(accepted.disclosure_items), 1)
            request = request_from_job_context(context)
            self.assertEqual(len(request.disclosures), 1)
            self.assertEqual(
                request.disclosures[0]["analysis_manifest_sha256"],
                context.analysis.manifest_sha256,
            )

    def test_analysis_manifest_sha_change_invalidates_confirmation(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            context, manifest = self._context(Path(folder))
            self._confirm_all(context)
            require_report_gate(context)

            payload = json.loads(manifest.read_text(encoding="utf-8"))
            payload["extra"] = "changed"
            manifest.write_text(json.dumps(payload), encoding="utf-8")
            context.analysis.manifest_sha256 = file_sha256(manifest)
            audit = inspect_report_gate(context)
            self.assertTrue(audit.missing_confirmation_ids)
            self.assertTrue(audit.stale_confirmation_ids)

    def test_unknown_or_failed_module_status_is_never_disclosable(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            context, _ = self._context(
                Path(folder),
                module_status="failed",
                module_message="设备断采",
            )
            audit = inspect_report_gate(context)
            self.assertTrue(audit.hard_issues)
            self.assertFalse(audit.disclosure_items)
            self.assertIn("分析结果包含失败项目", "；".join(audit.hard_issues))

    def test_explicit_no_data_status_can_be_disclosed_without_fake_plot(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            context, _ = self._context(
                Path(folder),
                module_status="no_data",
                module_message="本期设备断采，未形成有效样本",
                report_type="jlj_monthly",
            )
            audit = inspect_report_gate(context)
            self.assertFalse(audit.hard_issues)
            self.assertEqual(len(audit.disclosure_items), 1)
            self.assertEqual(audit.disclosure_items[0].reason_code, "no_valid_data")
            self._confirm_all(context)
            self.assertTrue(require_report_gate(context).passed)

    def test_report_type_without_safe_template_adapter_keeps_no_data_red(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            context, _ = self._context(
                Path(folder),
                module_status="no_data",
                module_message="本期设备断采，未形成有效样本",
                report_type="guanbing_monthly",
            )
            audit = inspect_report_gate(context)
            self.assertIn(
                "尚未实现这些黄色缺项的安全正文处置",
                "；".join(audit.hard_issues),
            )
            self.assertFalse(audit.disclosure_items)


if __name__ == "__main__":
    unittest.main()
