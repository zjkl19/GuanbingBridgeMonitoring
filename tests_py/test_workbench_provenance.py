from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from workbench.provenance import inspect_manifest_plot_provenance


ROOT = Path(__file__).resolve().parents[1]
CONTRACT = ROOT / "tests" / "fixtures" / "workbench_provenance_contract.json"


def source(*, incomplete_days: list[str] | None = None) -> dict[str, object]:
    days = incomplete_days or []
    return {
        "source_sample_count": 10,
        "finite_source_sample_count": 9,
        "completeness_scope": "required_export_contribution",
        "internal_gap_coverage_assessed": True,
        "calendar_day_count_requested": 2,
        "complete_day_count": 2 - len(days),
        "incomplete_day_count": len(days),
        "incomplete_days": days,
        "missing_required_sources": [],
    }


class WorkbenchProvenanceTests(unittest.TestCase):
    def test_shared_matlab_contract_fixture_closes(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            provenance = root / "A1.plot.json"
            provenance.write_bytes(CONTRACT.read_bytes())
            manifest = root / "analysis_manifest.json"
            manifest.write_text(json.dumps({
                "module_results": [{"key": "acceleration", "artifacts": [{"path": str(provenance)}]}],
            }), encoding="utf-8")
            summary = inspect_manifest_plot_provenance(manifest)
            self.assertEqual(summary.closed_count, 1)
            self.assertEqual(summary.incomplete_source_count, 1)
            self.assertEqual(summary.rows[0].source_count, 10)
            self.assertEqual(summary.rows[0].plotted_count, 9)

    def test_manifest_provenance_closure_and_disclosed_incomplete_days(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            complete = root / "A1.plot.json"
            incomplete = root / "A2.plot.json"
            for path, days in ((complete, []), (incomplete, ["2026-06-30"])):
                path.write_text(json.dumps({
                    "file_stub": path.name.removesuffix(".plot.json"),
                    "series": [{
                        "sampling_mode": "full",
                        "reduction_applied": False,
                        "input_count": 10,
                        "finite_count": 9,
                        "plotted_finite_count": 9,
                        "source": source(incomplete_days=days),
                    }],
                }), encoding="utf-8")
            manifest = root / "analysis_manifest.json"
            manifest.write_text(json.dumps({
                "module_results": [{
                    "key": "acceleration",
                    "artifacts": [
                        {"kind": "plot_provenance", "path": str(complete)},
                        {"kind": "plot_provenance", "path": str(incomplete)},
                    ],
                }],
            }), encoding="utf-8")
            summary = inspect_manifest_plot_provenance(manifest)
            self.assertEqual(summary.closed_count, 2)
            self.assertEqual(summary.failed_count, 0)
            self.assertEqual(summary.incomplete_source_count, 1)
            self.assertEqual(summary.rows[1].incomplete_days, ("2026-06-30",))

    def test_capped_or_count_mismatch_fails_closure(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            provenance = root / "A1.plot.json"
            provenance.write_text(json.dumps({
                "series": [{
                    "sampling_mode": "capped",
                    "reduction_applied": True,
                    "finite_count": 10,
                    "plotted_finite_count": 9,
                }],
            }), encoding="utf-8")
            manifest = root / "analysis_manifest.json"
            manifest.write_text(json.dumps({
                "module_results": [{"key": "acceleration", "artifacts": [str(provenance)]}],
            }), encoding="utf-8")
            summary = inspect_manifest_plot_provenance(manifest)
            self.assertEqual(summary.failed_count, 1)
            self.assertIn("not full", summary.rows[0].message)

    def test_duplicate_manifest_artifact_is_listed_once(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            provenance = root / "A1.plot.json"
            provenance.write_text(json.dumps({
                "series": [{
                    "sampling_mode": "full", "reduction_applied": False,
                    "finite_count": 1, "plotted_finite_count": 1,
                }],
            }), encoding="utf-8")
            manifest = root / "analysis_manifest.json"
            manifest.write_text(json.dumps({
                "module_results": [{"key": "acceleration", "artifacts": [
                    {"path": str(provenance)}, {"path": str(provenance)},
                ]}],
            }), encoding="utf-8")
            summary = inspect_manifest_plot_provenance(manifest)
            self.assertEqual(len(summary.rows), 1)
            self.assertEqual(summary.failed_count, 1)
            self.assertIn("缺少源数据", summary.rows[0].message)


if __name__ == "__main__":
    unittest.main()
