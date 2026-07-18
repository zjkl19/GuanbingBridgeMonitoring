from __future__ import annotations

import copy
import json
import tempfile
import unittest
from pathlib import Path

from reporting.locked_docx_media import (
    MediaCandidateError,
    PlotProvenanceContractError,
    validate_full_plot_provenance,
)
from workbench.provenance import inspect_manifest_plot_provenance


QUARTER_SOURCE_COUNT = 144_400_712
QUARTER_FINITE_SOURCE_COUNT = 144_400_711
QUARTER_DERIVED_INPUT_COUNT = 12_672
QUARTER_DERIVED_FINITE_COUNT = 12_032


def quarterly_wind_payload(file_stub: str) -> dict[str, object]:
    """Return Hongtang-scale metadata without allocating source-sized arrays."""

    return {
        "schema_version": 2,
        "file_stub": file_stub,
        "series": [
            {
                "schema_version": 2,
                "series_id": "W1",
                "sampling_mode": "full",
                "render_mode": "derived_10min_mean",
                "reduction_applied": False,
                "input_count": QUARTER_DERIVED_INPUT_COUNT,
                "finite_count": QUARTER_DERIVED_FINITE_COUNT,
                "plotted_finite_count": QUARTER_DERIVED_FINITE_COUNT,
                "render_input_count": QUARTER_DERIVED_INPUT_COUNT,
                "render_finite_input_count": QUARTER_DERIVED_FINITE_COUNT,
                "render_vertex_count": QUARTER_DERIVED_FINITE_COUNT,
                "source": {
                    "source_sample_count": QUARTER_SOURCE_COUNT,
                    "finite_source_sample_count": QUARTER_FINITE_SOURCE_COUNT,
                    "completeness_scope": "required_export_contribution",
                    "internal_gap_coverage_assessed": True,
                    "calendar_day_count_requested": 91,
                    "complete_day_count": 89,
                    "incomplete_day_count": 2,
                    "incomplete_days": ["2026-06-29", "2026-06-30"],
                    "missing_required_sources": ["2026-07-01 rolling source"],
                },
            }
        ],
    }


class WindDerivedProvenanceContractTests(unittest.TestCase):
    def _write_case(
        self,
        root: Path,
        payload: dict[str, object],
    ) -> tuple[Path, Path, Path]:
        candidate = root / "W1_speed10min_2026-04-01_2026-06-30.png"
        candidate.write_bytes(b"metadata-contract-only")
        provenance = candidate.with_suffix(".plot.json")
        provenance.write_text(json.dumps(payload), encoding="utf-8")
        manifest = root / "analysis_manifest.json"
        manifest.write_text(
            json.dumps(
                {"module_results": [{"key": "wind", "artifacts": [str(provenance)]}]}
            ),
            encoding="utf-8",
        )
        return candidate, provenance, manifest

    def test_quarter_scale_derived_counts_close_in_workbench_and_report(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            stub = "W1_speed10min_2026-04-01_2026-06-30"
            payload = quarterly_wind_payload(stub)
            candidate, provenance, manifest = self._write_case(root, payload)

            self.assertLess(len(provenance.read_bytes()), 4_096)
            summary = inspect_manifest_plot_provenance(manifest)
            self.assertEqual(summary.closed_count, 1)
            self.assertEqual(summary.failed_count, 0)
            self.assertEqual(summary.rows[0].source_count, QUARTER_SOURCE_COUNT)
            self.assertEqual(summary.rows[0].plotted_count, QUARTER_DERIVED_FINITE_COUNT)
            self.assertEqual(summary.rows[0].status, "closed_incomplete_source")
            self.assertEqual(
                validate_full_plot_provenance(
                    provenance,
                    candidate,
                    require_source_provenance=True,
                ),
                1,
            )

    def test_legacy_mixed_raw_and_derived_counts_fail_both_consumers(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            stub = "W1_speed10min_2026-04-01_2026-06-30"
            payload = quarterly_wind_payload(stub)
            series = payload["series"][0]
            assert isinstance(series, dict)
            series["input_count"] = QUARTER_SOURCE_COUNT
            series["finite_count"] = QUARTER_FINITE_SOURCE_COUNT
            series["reduction_applied"] = True
            candidate, provenance, manifest = self._write_case(root, payload)

            summary = inspect_manifest_plot_provenance(manifest)
            self.assertEqual(summary.failed_count, 1)
            self.assertEqual(summary.rows[0].failure_code, "derived_reduction_forbidden")
            self.assertIn("10分钟派生序列", summary.rows[0].reason_zh)
            with self.assertRaises(PlotProvenanceContractError) as caught:
                validate_full_plot_provenance(
                    provenance,
                    candidate,
                    require_source_provenance=True,
                )
            self.assertEqual(caught.exception.code, "derived_reduction_forbidden")
            self.assertIn("修复建议", str(caught.exception))

    def test_impossible_source_or_derived_plot_counts_fail_both_consumers(self) -> None:
        cases = {
            "source_below_derived": {
                "source": {
                    "source_sample_count": 12_000,
                    "finite_source_sample_count": 11_999,
                }
            },
            "finite_not_fully_plotted": {"plotted_finite_count": 12_031},
            "render_counts_fake_full_plot": {
                "render_input_count": 1,
                "render_finite_input_count": 1,
                "render_vertex_count": 1,
            },
            "fractional_day_counts": {
                "source": {
                    "calendar_day_count_requested": 91.5,
                    "complete_day_count": 89.5,
                    "incomplete_day_count": 2.5,
                }
            },
            "fractional_source_count": {
                "source": {"source_sample_count": 144_400_712.5}
            },
            "fractional_derived_count": {"input_count": 12_672.5},
        }
        for label, overrides in cases.items():
            with self.subTest(label=label), tempfile.TemporaryDirectory() as folder:
                root = Path(folder)
                stub = "W1_speed10min_2026-04-01_2026-06-30"
                payload = quarterly_wind_payload(stub)
                payload = copy.deepcopy(payload)
                series = payload["series"][0]
                assert isinstance(series, dict)
                source_overrides = overrides.get("source")
                if isinstance(source_overrides, dict):
                    source = series["source"]
                    assert isinstance(source, dict)
                    source.update(source_overrides)
                series.update({key: value for key, value in overrides.items() if key != "source"})
                candidate, provenance, manifest = self._write_case(root, payload)

                summary = inspect_manifest_plot_provenance(manifest)
                self.assertEqual(summary.failed_count, 1)
                if label == "render_counts_fake_full_plot":
                    self.assertEqual(
                        summary.rows[0].failure_code,
                        "derived_render_counts_not_closed",
                    )
                elif label == "fractional_day_counts":
                    self.assertEqual(summary.rows[0].failure_code, "invalid_day_count")
                elif label.startswith("fractional_"):
                    self.assertEqual(summary.rows[0].failure_code, "invalid_count")
                with self.assertRaises(MediaCandidateError):
                    validate_full_plot_provenance(
                        provenance,
                        candidate,
                        require_source_provenance=True,
                    )


if __name__ == "__main__":
    unittest.main()
