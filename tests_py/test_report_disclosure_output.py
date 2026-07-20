from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock, patch
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "reporting"))

from report_disclosure_output import (  # noqa: E402
    DisclosureReviewRequired,
    reconcile_and_apply_disclosures,
)
from report_job import build_qc  # noqa: E402
from report_job_cli import run_context  # noqa: E402
from tests_py.locked_docx_media_test_utils import create_minimal_docx  # noqa: E402
from workbench.report_disclosures import (  # noqa: E402
    DISCLOSURE_POLICY_VERSION,
    confirmation_record,
    report_build_disclosure_item,
)


class ReportDisclosureOutputTests(unittest.TestCase):
    def _draft(self, root: Path, missing_items: list[dict]) -> tuple[Path, Path, Path]:
        report = create_minimal_docx(root / "report.docx")
        analysis = root / "analysis_manifest.json"
        analysis.write_text('{"status":"ok"}', encoding="utf-8")
        manifest = root / "report_build_manifest.json"
        manifest.write_text(json.dumps({
            "status": "warning" if missing_items else "ok",
            "missing_count": len(missing_items),
            "missing_items": missing_items,
            "warnings": [],
            "output_docx": str(report),
        }, ensure_ascii=False), encoding="utf-8")
        return report, manifest, analysis

    def test_safe_builder_gap_requires_review_then_becomes_disclosed_formal_report(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            report, manifest, analysis = self._draft(root, [{
                "category": "章节内容缺失",
                "label": "2.3 车辆荷载",
                "detail": "本月设备断采，未获取到有效数据。",
            }])
            with self.assertRaises(DisclosureReviewRequired) as raised:
                reconcile_and_apply_disclosures(
                    report_type="jlj_monthly",
                    report_path=report,
                    manifest_path=manifest,
                    analysis_manifest_path=analysis,
                    analysis_manifest_sha256="A" * 64,
                    approved_disclosures=(),
                )
            candidate = raised.exception.candidates[0]
            review_payload = json.loads(manifest.read_text(encoding="utf-8"))
            self.assertEqual(review_payload["status"], "disclosure_review_required")
            self.assertEqual(review_payload["disclosure_count"], 1)

            approval = confirmation_record(
                candidate,
                analysis_manifest_sha256="A" * 64,
                confirmed_at="2026-07-18T12:00:00+08:00",
            )
            disclosures, payload = reconcile_and_apply_disclosures(
                report_type="jlj_monthly",
                report_path=report,
                manifest_path=manifest,
                analysis_manifest_path=analysis,
                analysis_manifest_sha256="A" * 64,
                approved_disclosures=(approval,),
            )

            self.assertEqual(len(disclosures), 1)
            self.assertEqual(payload["status"], "passed_with_disclosures")
            self.assertEqual(payload["disclosure_count"], 1)
            self.assertEqual(
                payload["missing_items"][0]["disclosure_stable_id"],
                candidate.stable_id,
            )
            with ZipFile(report) as archive:
                document_xml = archive.read("word/document.xml").decode("utf-8")
            self.assertIn("缺项与数据完整性披露", document_xml)
            self.assertIn("本月设备断采", document_xml)
            self.assertNotIn("2.3 车辆荷载：2.3 车辆荷载：", document_xml)

            qc = build_qc(
                report,
                manifest,
                None,
                {"status": "passed", "page_count": 1, "pages": []},
                require_source_provenance=True,
            )
            self.assertEqual(qc["status"], "passed_with_disclosures")
            self.assertEqual(qc["manifest"]["disclosure_count"], 1)

    def test_unknown_or_qc_missing_item_remains_hard_blocker(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            report, manifest, analysis = self._draft(root, [{
                "category": "report_qc",
                "label": "stale_template_image",
                "detail": "模板旧媒体仍然存在",
            }])
            with self.assertRaisesRegex(RuntimeError, "不可人工放行"):
                reconcile_and_apply_disclosures(
                    report_type="jlj_monthly",
                    report_path=report,
                    manifest_path=manifest,
                    analysis_manifest_path=analysis,
                    analysis_manifest_sha256="A" * 64,
                    approved_disclosures=(),
                )

    def test_changed_builder_gap_invalidates_old_confirmation(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            report, manifest, analysis = self._draft(root, [{
                "category": "巡查资料缺失",
                "label": "2026-06",
                "detail": "本月巡查资料缺失",
            }])
            with self.assertRaises(DisclosureReviewRequired) as raised:
                reconcile_and_apply_disclosures(
                    report_type="jlj_monthly",
                    report_path=report,
                    manifest_path=manifest,
                    analysis_manifest_path=analysis,
                    analysis_manifest_sha256="B" * 64,
                    approved_disclosures=(),
                )
            old = confirmation_record(
                raised.exception.candidates[0],
                analysis_manifest_sha256="B" * 64,
            )
            payload = json.loads(manifest.read_text(encoding="utf-8"))
            payload["missing_items"][0]["detail"] = "缺失原因发生变化"
            manifest.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")

            with self.assertRaises(DisclosureReviewRequired) as changed:
                reconcile_and_apply_disclosures(
                    report_type="jlj_monthly",
                    report_path=report,
                    manifest_path=manifest,
                    analysis_manifest_path=analysis,
                    analysis_manifest_sha256="B" * 64,
                    approved_disclosures=(old,),
                )
            self.assertNotEqual(
                changed.exception.candidates[0].stable_id,
                old["stable_id"],
            )

    def test_confirmation_policy_version_is_recorded(self) -> None:
        self.assertGreaterEqual(DISCLOSURE_POLICY_VERSION, 1)

    def test_jlj_source_coverage_note_is_a_sha_bound_disclosure(self) -> None:
        item = report_build_disclosure_item(
            "jlj_monthly",
            {
                "category": "数据完整性披露",
                "label": "监测数据有效覆盖边界",
                "detail": "6月18日至30日无有效源数据，不插补。",
                "module_key": "source_coverage",
            },
        )
        self.assertIsNotNone(item)
        assert item is not None
        self.assertEqual(item.reason_code, "incomplete_source_coverage")
        self.assertIn("不插补缺失时段", item.action_zh)

    def test_worker_publishes_review_required_as_expected_terminal_state(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            report, manifest, _analysis = self._draft(root, [])
            candidate = report_build_disclosure_item(
                "jlj_monthly",
                {
                    "category": "巡查资料缺失",
                    "label": "2026-06",
                    "detail": "本月巡查资料缺失",
                },
            )
            assert candidate is not None
            context = Mock()
            context.report.launch_id = "review-launch"
            context.analysis.manifest_sha256 = "C" * 64
            status_path = root / "status.json"
            result_path = root / "result.json"
            with patch("report_job_cli.JobContext.read", return_value=context), patch(
                "report_job_cli.request_from_context", return_value=Mock()
            ), patch(
                "report_job_cli.execute_report_job",
                side_effect=DisclosureReviewRequired((candidate,), report, manifest),
            ):
                code = run_context(
                    root / "context.json",
                    status_path,
                    result_path,
                    expected_launch_id="review-launch",
                )
            self.assertEqual(code, 0)
            result = json.loads(result_path.read_text(encoding="utf-8"))
            status = json.loads(status_path.read_text(encoding="utf-8"))
            self.assertEqual(result["state"], "disclosure_required")
            self.assertEqual(status["stage"], "disclosure_review")
            self.assertEqual(result["disclosure_count"], 1)
            self.assertEqual(
                result["analysis_manifest_sha256"],
                context.analysis.manifest_sha256,
            )


if __name__ == "__main__":
    unittest.main()
