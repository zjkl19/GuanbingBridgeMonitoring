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


def reduced_v2_series(**overrides: object) -> dict[str, object]:
    series: dict[str, object] = {
        "schema_version": 2,
        "sampling_mode": "full",
        "render_mode": "line",
        "plot_scope": "point_time_history",
        "reduction_applied": True,
        "reduction_scope": "render_only",
        "reduction_algorithm": "peak_preserving_bucket_minmax_v1",
        "extrema_preserved": True,
        "first_last_preserved": True,
        "input_count": 10,
        "finite_count": 9,
        "plotted_finite_count": 5,
        "render_input_count": 6,
        "render_finite_input_count": 5,
        "render_vertex_count": 5,
        "source": source(),
    }
    series.update(overrides)
    return series


class WorkbenchProvenanceTests(unittest.TestCase):
    def test_reduced_full_v2_peak_preserving_render_closes(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            provenance = root / "A1.plot.json"
            provenance.write_text(json.dumps({
                "schema_version": 2,
                "series": [reduced_v2_series()],
            }), encoding="utf-8")
            manifest = root / "analysis_manifest.json"
            manifest.write_text(json.dumps({
                "module_results": [{"key": "acceleration", "artifacts": [str(provenance)]}],
            }), encoding="utf-8")

            summary = inspect_manifest_plot_provenance(manifest)

            self.assertEqual(summary.closed_count, 1)
            self.assertEqual(summary.failed_count, 0)
            self.assertEqual(summary.rows[0].source_count, 10)
            self.assertEqual(summary.rows[0].plotted_count, 5)

    def test_reduced_full_v2_contract_fails_closed_for_unsafe_variants(self) -> None:
        cases: list[tuple[str, int, dict[str, object], str]] = [
            ("legacy_schema", 1, {}, "schema_version>=2"),
            ("series_legacy_schema", 2, {"schema_version": 1}, "series schema_version>=2"),
            ("missing_input_count", 2, {}, "explicit input_count"),
            ("not_render_only", 2, {"reduction_scope": "analysis"}, "render_only"),
            ("unknown_algorithm", 2, {"reduction_algorithm": "lttb"}, "unsupported"),
            ("extrema_not_preserved", 2, {"extrema_preserved": False}, "preserve extrema"),
            ("endpoints_not_preserved", 2, {"first_last_preserved": False}, "first/last"),
            ("render_count_mismatch", 2, {"render_vertex_count": 4}, "render/plotted"),
            ("missing_render_input", 2, {}, "explicit render_input_count"),
            ("missing_render_finite", 2, {}, "explicit render_finite_input_count"),
            ("negative_render_input", 2, {"render_input_count": -1}, "non-negative"),
            (
                "render_input_below_finite",
                2,
                {"render_input_count": 4, "render_finite_input_count": 5},
                "source/render input counts",
            ),
            (
                "render_finite_below_plotted",
                2,
                {"render_finite_input_count": 4},
                "source/render input counts",
            ),
            (
                "source_below_render_input",
                2,
                {"render_input_count": 11},
                "source/render input counts",
            ),
            ("source_count_mismatch", 2, {"input_count": 9}, "raw source/input/finite"),
        ]
        for label, schema_version, overrides, expected in cases:
            with self.subTest(label=label), tempfile.TemporaryDirectory() as folder:
                root = Path(folder)
                provenance = root / "A1.plot.json"
                series = reduced_v2_series(**overrides)
                if label == "missing_input_count":
                    series.pop("input_count")
                elif label == "missing_render_input":
                    series.pop("render_input_count")
                elif label == "missing_render_finite":
                    series.pop("render_finite_input_count")
                provenance.write_text(json.dumps({
                    "schema_version": schema_version,
                    "series": [series],
                }), encoding="utf-8")
                manifest = root / "analysis_manifest.json"
                manifest.write_text(json.dumps({
                    "module_results": [{
                        "key": "acceleration",
                        "artifacts": [str(provenance)],
                    }],
                }), encoding="utf-8")

                summary = inspect_manifest_plot_provenance(manifest)

                self.assertEqual(summary.failed_count, 1)
                self.assertIn(expected, summary.rows[0].message)
                if label == "source_count_mismatch":
                    self.assertEqual(summary.rows[0].failure_code, "raw_counts_not_closed")
                    self.assertIn("原始序列", summary.rows[0].reason_zh)

    def test_reduced_full_v2_requires_source_provenance(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            provenance = root / "A1.plot.json"
            series = reduced_v2_series()
            series.pop("source")
            provenance.write_text(json.dumps({
                "schema_version": 2,
                "series": [series],
            }), encoding="utf-8")
            manifest = root / "analysis_manifest.json"
            manifest.write_text(json.dumps({
                "module_results": [{"key": "acceleration", "artifacts": [str(provenance)]}],
            }), encoding="utf-8")

            summary = inspect_manifest_plot_provenance(manifest)

            self.assertEqual(summary.failed_count, 1)

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
            self.assertIn("requires full sampling", summary.rows[0].message)

    def test_capped_raw_wind_and_earthquake_close_with_explicit_module_context(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            artifacts = []
            module_results = []
            for module in ("wind", "earthquake"):
                provenance = root / f"{module}.plot.json"
                provenance.write_text(json.dumps({
                    "series": [{
                        "sampling_mode": "capped",
                        "render_mode": "line",
                        "reduction_applied": True,
                        "input_count": 8,
                        "finite_count": 7,
                        "plotted_finite_count": 5,
                        "source": source(),
                    }],
                }), encoding="utf-8")
                artifacts.append(provenance)
                module_results.append({"key": module, "artifacts": [str(provenance)]})
            manifest = root / "analysis_manifest.json"
            manifest.write_text(json.dumps({"module_results": module_results}), encoding="utf-8")

            summary = inspect_manifest_plot_provenance(manifest)

            self.assertEqual(summary.closed_count, 2)
            self.assertEqual(summary.failed_count, 0)
            self.assertEqual([row.module_key for row in summary.rows], ["wind", "earthquake"])

    def test_capped_raw_series_rejects_missing_module_or_inconsistent_reduction(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            missing_module = root / "missing_module.plot.json"
            bad_reduction = root / "bad_reduction.plot.json"
            base = {
                "sampling_mode": "capped",
                "render_mode": "line",
                "reduction_applied": True,
                "input_count": 8,
                "finite_count": 7,
                "plotted_finite_count": 5,
                "source": source(),
            }
            missing_module.write_text(json.dumps({"series": [base]}), encoding="utf-8")
            mismatch = dict(base)
            mismatch["reduction_applied"] = False
            bad_reduction.write_text(json.dumps({"series": [mismatch]}), encoding="utf-8")
            manifest = root / "analysis_manifest.json"
            manifest.write_text(json.dumps({
                "module_results": [{"key": "wind", "artifacts": [str(bad_reduction)]}],
                "artifacts": [str(missing_module)],
            }), encoding="utf-8")

            summary = inspect_manifest_plot_provenance(manifest)

            self.assertEqual(summary.failed_count, 2)
            messages = "\n".join(row.message for row in summary.rows)
            self.assertIn("reduction flag", messages)
            self.assertIn("lacks a manifest module key", messages)

    def test_capped_acceleration_group_overview_is_explicitly_allowed(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            provenance = root / "acceleration_group.plot.json"
            provenance.write_text(json.dumps({
                "series": [{
                    "sampling_mode": "capped",
                    "render_mode": "line",
                    "plot_scope": "group_overview",
                    "reduction_applied": True,
                    "input_count": 10,
                    "finite_count": 9,
                    "plotted_finite_count": 5,
                    "source": source(),
                }],
            }), encoding="utf-8")
            manifest = root / "analysis_manifest.json"
            manifest.write_text(json.dumps({
                "module_results": [{"key": "acceleration", "artifacts": [str(provenance)]}],
            }), encoding="utf-8")

            summary = inspect_manifest_plot_provenance(manifest)

            self.assertEqual(summary.closed_count, 1)
            self.assertEqual(summary.failed_count, 0)

    def test_unknown_group_scope_does_not_bypass_full_acceleration_gate(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            provenance = root / "acceleration_unknown_scope.plot.json"
            provenance.write_text(json.dumps({
                "series": [{
                    "sampling_mode": "capped",
                    "render_mode": "line",
                    "plot_scope": "overview_typo",
                    "reduction_applied": True,
                    "input_count": 10,
                    "finite_count": 9,
                    "plotted_finite_count": 5,
                    "source": source(),
                }],
            }), encoding="utf-8")
            manifest = root / "analysis_manifest.json"
            manifest.write_text(json.dumps({
                "module_results": [{"key": "acceleration", "artifacts": [str(provenance)]}],
            }), encoding="utf-8")

            summary = inspect_manifest_plot_provenance(manifest)

            self.assertEqual(summary.failed_count, 1)
            self.assertIn("unsupported plot_scope", summary.rows[0].message)

    def test_derived_series_rejects_capped_sampling_even_when_counts_close(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            provenance = root / "W1_10min.plot.json"
            provenance.write_text(json.dumps({
                "schema_version": 2,
                "series": [{
                    "schema_version": 2,
                    "sampling_mode": "capped",
                    "render_mode": "derived_10min_mean",
                    "reduction_applied": False,
                    "input_count": 10,
                    "finite_count": 9,
                    "plotted_finite_count": 9,
                    "render_input_count": 10,
                    "render_finite_input_count": 9,
                    "render_vertex_count": 9,
                    "source": source(),
                }],
            }), encoding="utf-8")
            manifest = root / "analysis_manifest.json"
            manifest.write_text(json.dumps({
                "module_results": [{"key": "wind", "artifacts": [str(provenance)]}],
            }), encoding="utf-8")

            summary = inspect_manifest_plot_provenance(manifest)

            self.assertEqual(summary.failed_count, 1)
            self.assertIn("must use full sampling", summary.rows[0].message)

    def test_unknown_render_mode_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            provenance = root / "unknown.plot.json"
            provenance.write_text(json.dumps({
                "series": [{
                    "sampling_mode": "full",
                    "render_mode": "mystery_aggregate",
                    "reduction_applied": False,
                    "input_count": 10,
                    "finite_count": 9,
                    "plotted_finite_count": 9,
                    "source": source(),
                }],
            }), encoding="utf-8")
            manifest = root / "analysis_manifest.json"
            manifest.write_text(json.dumps({
                "module_results": [{"key": "wind", "artifacts": [str(provenance)]}],
            }), encoding="utf-8")

            summary = inspect_manifest_plot_provenance(manifest)

            self.assertEqual(summary.failed_count, 1)
            self.assertIn("unsupported render_mode", summary.rows[0].message)

    def test_derived_series_close_against_larger_raw_sources(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            provenance = root / "W1.plot.json"
            raw_source = source()
            raw_source["source_sample_count"] = 1000
            raw_source["finite_source_sample_count"] = 900
            provenance.write_text(json.dumps({
                "schema_version": 2,
                "series": [
                    {
                        "schema_version": 2,
                        "sampling_mode": "full",
                        "render_mode": "derived_10min_mean",
                        "reduction_applied": False,
                        "input_count": 100,
                        "finite_count": 90,
                        "plotted_finite_count": 90,
                        "render_input_count": 100,
                        "render_finite_input_count": 90,
                        "render_vertex_count": 90,
                        "source": raw_source,
                    },
                    {
                        "sampling_mode": "full",
                        "render_mode": "wind_rose_aggregate",
                        "reduction_applied": False,
                        "input_count": 800,
                        "finite_count": 750,
                        "plotted_finite_count": 700,
                        "source": raw_source,
                    },
                ],
            }), encoding="utf-8")
            manifest = root / "analysis_manifest.json"
            manifest.write_text(json.dumps({
                "module_results": [{"key": "wind", "artifacts": [str(provenance)]}],
            }), encoding="utf-8")

            summary = inspect_manifest_plot_provenance(manifest)

            self.assertEqual(summary.closed_count, 1)
            self.assertEqual(summary.failed_count, 0)
            self.assertEqual(summary.rows[0].source_count, 2000)
            self.assertEqual(summary.rows[0].plotted_count, 790)

    def test_derived_series_reject_impossible_source_or_plot_counts(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            provenance = root / "W1.plot.json"
            provenance.write_text(json.dumps({
                "schema_version": 2,
                "series": [{
                    "schema_version": 2,
                    "sampling_mode": "full",
                    "render_mode": "derived_10min_mean",
                    "reduction_applied": False,
                    "input_count": 11,
                    "finite_count": 10,
                    "plotted_finite_count": 10,
                    "render_input_count": 11,
                    "render_finite_input_count": 10,
                    "render_vertex_count": 10,
                    "source": source(),
                }],
            }), encoding="utf-8")
            manifest = root / "analysis_manifest.json"
            manifest.write_text(json.dumps({
                "module_results": [{"key": "wind", "artifacts": [str(provenance)]}],
            }), encoding="utf-8")

            summary = inspect_manifest_plot_provenance(manifest)

            self.assertEqual(summary.failed_count, 1)
            self.assertIn("source/input/finite", summary.rows[0].message)

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
