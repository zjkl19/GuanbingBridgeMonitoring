from __future__ import annotations

import json
import os
import sys
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
REPORTING_ROOT = REPO_ROOT / "reporting"
TESTS_ROOT = Path(__file__).resolve().parent
for candidate in (REPORTING_ROOT, TESTS_ROOT):
    if str(candidate) not in sys.path:
        sys.path.insert(0, str(candidate))

from locked_docx_media import MediaCandidateError, apply_media_plan, sha256_file  # noqa: E402
from locked_docx_media_test_utils import (  # noqa: E402
    create_minimal_docx,
    write_analysis_manifest,
    write_plot_provenance,
    write_png,
)
from report_media_plan import (  # noqa: E402
    ExplicitMediaBinding,
    MediaPlanError,
    compile_media_plan,
    load_explicit_bindings,
    load_media_plan,
    media_plan_to_dict,
    write_media_plan,
)


MEMBER = "word/media/image1.png"


def valid_source_provenance(**overrides: object) -> dict[str, object]:
    source: dict[str, object] = {
        "source_sample_count": 10,
        "finite_source_sample_count": 10,
        "completeness_scope": "required_export_contribution",
        "internal_gap_coverage_assessed": False,
        "calendar_day_count_requested": 2,
        "complete_day_count": 1,
        "incomplete_day_count": 1,
        "incomplete_days": ["2026-04-02"],
        "missing_required_sources": ["2026-04-03"],
    }
    source.update(overrides)
    return source


def write_reduced_v2_provenance(
    candidate: Path,
    *,
    provenance_schema_version: int = 2,
    **overrides: object,
) -> Path:
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
        "finite_count": 10,
        "plotted_finite_count": 6,
        "render_input_count": 7,
        "render_finite_input_count": 6,
        "render_vertex_count": 6,
        "source": valid_source_provenance(),
    }
    series.update(overrides)
    provenance = candidate.with_suffix(".plot.json")
    provenance.write_text(json.dumps({
        "schema_version": provenance_schema_version,
        "file_stub": candidate.stem,
        "series": [series],
    }), encoding="utf-8")
    return provenance


class ReportMediaPlanTests(unittest.TestCase):
    def test_explicit_binding_does_not_select_newer_file(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            baseline = create_minimal_docx(root / "baseline.docx")
            explicitly_bound = write_png(root / "explicit.png", "blue")
            newer_unbound = write_png(root / "newer.png", "green")
            os.utime(explicitly_bound, (1000, 1000))
            os.utime(newer_unbound, (2000, 2000))

            plan = compile_media_plan(
                baseline,
                [ExplicitMediaBinding("demo.figure", MEMBER, explicitly_bound)],
            )

            self.assertEqual(plan.replacements[0].candidate_path, explicitly_bound.resolve())
            self.assertEqual(plan.replacements[0].candidate_sha256, sha256_file(explicitly_bound))
            self.assertNotEqual(plan.replacements[0].candidate_sha256, sha256_file(newer_unbound))

    def test_bindings_json_resolves_relative_candidate_and_round_trips_plan(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            baseline = create_minimal_docx(root / "baseline.docx")
            candidate = write_png(root / "candidate.png", "blue")
            bindings_path = root / "bindings.json"
            bindings_path.write_text(
                json.dumps(
                    {
                        "bindings": [
                            {
                                "slot_id": "demo.figure",
                                "member": MEMBER,
                                "candidate_path": candidate.name,
                                "expected_width_px": 20,
                                "expected_height_px": 10,
                                "expected_format": "PNG",
                            }
                        ]
                    }
                ),
                encoding="utf-8",
            )
            plan = compile_media_plan(baseline, load_explicit_bindings(bindings_path))
            plan_path = write_media_plan(plan, root / "plan.json")

            loaded = load_media_plan(plan_path)
            self.assertEqual(media_plan_to_dict(loaded), media_plan_to_dict(plan))
            output = root / "output.docx"
            apply_media_plan(loaded, output)
            self.assertTrue(output.exists())

    def test_same_aspect_policy_round_trips_with_pinned_candidate_dimensions(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            baseline = create_minimal_docx(root / "baseline.docx")
            candidate = write_png(root / "candidate.png", "blue", (40, 20))
            bindings_path = root / "bindings.json"
            bindings_path.write_text(
                json.dumps(
                    {
                        "bindings": [
                            {
                                "slot_id": "demo.figure",
                                "member": MEMBER,
                                "candidate_path": candidate.name,
                                "dimension_policy": "same_aspect_or_larger",
                                "max_aspect_ratio_error": 0.0005,
                            }
                        ]
                    }
                ),
                encoding="utf-8",
            )

            plan = compile_media_plan(baseline, load_explicit_bindings(bindings_path))
            loaded = load_media_plan(write_media_plan(plan, root / "plan.json"))

            self.assertEqual(media_plan_to_dict(loaded), media_plan_to_dict(plan))
            replacement = loaded.replacements[0]
            self.assertEqual(replacement.dimension_policy, "same_aspect_or_larger")
            self.assertEqual(replacement.max_aspect_ratio_error, 0.0005)
            self.assertEqual(
                (replacement.candidate_width_px, replacement.candidate_height_px),
                (40, 20),
            )

    def test_legacy_v1_plan_without_dimension_policy_loads_as_exact(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            baseline = create_minimal_docx(root / "baseline.docx")
            candidate = write_png(root / "candidate.png", "blue")
            plan = compile_media_plan(
                baseline,
                [ExplicitMediaBinding("demo.figure", MEMBER, candidate)],
            )
            payload = media_plan_to_dict(plan)
            payload["schema_version"] = 1
            for record in payload["replacements"]:
                for key in (
                    "candidate_width_px",
                    "candidate_height_px",
                    "dimension_policy",
                    "max_aspect_ratio_error",
                    "require_source_provenance",
                ):
                    record.pop(key)
            legacy_path = root / "legacy-v1-plan.json"
            legacy_path.write_text(json.dumps(payload), encoding="utf-8")

            loaded = load_media_plan(legacy_path)
            replacement = loaded.replacements[0]
            self.assertEqual(replacement.dimension_policy, "exact")
            self.assertFalse(replacement.require_source_provenance)
            self.assertEqual(
                (replacement.candidate_width_px, replacement.candidate_height_px),
                (replacement.width_px, replacement.height_px),
            )
            apply_media_plan(loaded, root / "legacy-output.docx")

    def test_v2_plan_requires_positive_pinned_candidate_dimensions(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            baseline = create_minimal_docx(root / "baseline.docx")
            candidate = write_png(root / "candidate.png", "blue")
            payload = media_plan_to_dict(
                compile_media_plan(
                    baseline,
                    [ExplicitMediaBinding("demo.figure", MEMBER, candidate)],
                )
            )
            for label, value in (("missing", None), ("zero", 0)):
                with self.subTest(label=label):
                    record = payload["replacements"][0]
                    if value is None:
                        record.pop("candidate_width_px", None)
                    else:
                        record["candidate_width_px"] = value
                    plan_path = root / f"invalid-v2-{label}.json"
                    plan_path.write_text(json.dumps(payload), encoding="utf-8")
                    with self.assertRaises(MediaPlanError):
                        load_media_plan(plan_path)
                    record["candidate_width_px"] = 20

    def test_same_aspect_policy_enforces_requested_tolerance(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            baseline = create_minimal_docx(root / "baseline.docx")
            inside = write_png(root / "inside.png", "blue", (1001, 500))
            outside = write_png(root / "outside.png", "blue", (1002, 500))

            compile_media_plan(
                baseline,
                [
                    ExplicitMediaBinding(
                        "inside",
                        MEMBER,
                        inside,
                        dimension_policy="same_aspect_or_larger",
                        max_aspect_ratio_error=0.00101,
                    )
                ],
            )
            with self.assertRaises(MediaCandidateError):
                compile_media_plan(
                    baseline,
                    [
                        ExplicitMediaBinding(
                            "outside",
                            MEMBER,
                            outside,
                            dimension_policy="same_aspect_or_larger",
                            max_aspect_ratio_error=0.00101,
                        )
                    ],
                )

    def test_invalid_dimension_policy_or_tolerance_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            candidate = write_png(root / "candidate.png", "blue")
            for label, extra in (
                ("policy", {"dimension_policy": "resize_anything"}),
                ("negative_tolerance", {"max_aspect_ratio_error": -0.1}),
                ("large_tolerance", {"max_aspect_ratio_error": 0.02}),
                ("boolean_tolerance", {"max_aspect_ratio_error": False}),
                ("nan_tolerance", {"max_aspect_ratio_error": float("nan")}),
                ("infinite_tolerance", {"max_aspect_ratio_error": float("inf")}),
            ):
                with self.subTest(label=label):
                    bindings_path = root / f"{label}.json"
                    bindings_path.write_text(
                        json.dumps(
                            {
                                "bindings": [
                                    {
                                        "slot_id": "demo.figure",
                                        "member": MEMBER,
                                        "candidate_path": str(candidate),
                                        **extra,
                                    }
                                ]
                            }
                        ),
                        encoding="utf-8",
                    )
                    with self.assertRaises(MediaPlanError):
                        load_explicit_bindings(bindings_path)

    def test_explicit_analysis_manifest_is_pinned_by_hash(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            baseline = create_minimal_docx(root / "baseline.docx")
            candidate = write_png(root / "candidate.png", "blue")
            provenance = write_plot_provenance(candidate)
            manifest = root / "analysis_manifest_explicit.json"
            write_analysis_manifest(manifest, [[candidate, provenance]])

            plan = compile_media_plan(
                baseline,
                [ExplicitMediaBinding("demo.figure", MEMBER, candidate)],
                analysis_manifest_path=manifest,
            )

            self.assertEqual(plan.source_manifest_path, manifest.resolve())
            self.assertEqual(plan.source_manifest_sha256, sha256_file(manifest))
            self.assertEqual(plan.source_manifest_status, "ok")
            self.assertEqual(plan.replacements[0].provenance_path, provenance.resolve())
            self.assertEqual(plan.replacements[0].provenance_sha256, sha256_file(provenance))
            self.assertEqual(plan.replacements[0].provenance_series_count, 1)
            self.assertTrue(plan.replacements[0].manifest_artifact_record)
            loaded = load_media_plan(write_media_plan(plan, root / "manifest_bound_plan.json"))
            self.assertEqual(media_plan_to_dict(loaded), media_plan_to_dict(plan))
            apply_media_plan(loaded, root / "manifest_bound_output.docx")

    def test_failed_or_implicit_manifest_is_not_substituted(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            baseline = create_minimal_docx(root / "baseline.docx")
            candidate = write_png(root / "candidate.png", "blue")
            failed = root / "analysis_manifest_failed.json"
            failed.write_text('{"status":"failed"}', encoding="utf-8")
            newer_ok = root / "analysis_manifest_newer.json"
            newer_ok.write_text('{"status":"ok"}', encoding="utf-8")
            os.utime(failed, (1000, 1000))
            os.utime(newer_ok, (2000, 2000))

            with self.assertRaises(MediaPlanError):
                compile_media_plan(
                    baseline,
                    [ExplicitMediaBinding("demo.figure", MEMBER, candidate)],
                    analysis_manifest_path=failed,
                )

    def test_duplicate_explicit_member_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            baseline = create_minimal_docx(root / "baseline.docx")
            candidate = write_png(root / "candidate.png", "blue")
            with self.assertRaises(MediaPlanError):
                compile_media_plan(
                    baseline,
                    [
                        ExplicitMediaBinding("one", MEMBER, candidate),
                        ExplicitMediaBinding("two", MEMBER, candidate),
                    ],
                )

    def test_manifest_bound_candidate_requires_provenance(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            baseline = create_minimal_docx(root / "baseline.docx")
            candidate = write_png(root / "candidate.png", "blue")
            manifest = write_analysis_manifest(
                root / "analysis_manifest.json",
                [[candidate]],
            )

            with self.assertRaises(MediaCandidateError):
                compile_media_plan(
                    baseline,
                    [ExplicitMediaBinding("demo.figure", MEMBER, candidate)],
                    analysis_manifest_path=manifest,
                )

    def test_candidate_and_provenance_must_belong_to_same_manifest_record(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            baseline = create_minimal_docx(root / "baseline.docx")
            candidate = write_png(root / "candidate.png", "blue")
            provenance = write_plot_provenance(candidate)

            missing_candidate_manifest = write_analysis_manifest(
                root / "manifest_missing_candidate.json",
                [[provenance]],
            )
            with self.assertRaises(MediaCandidateError):
                compile_media_plan(
                    baseline,
                    [ExplicitMediaBinding("demo.figure", MEMBER, candidate)],
                    analysis_manifest_path=missing_candidate_manifest,
                )

            split_manifest = write_analysis_manifest(
                root / "manifest_split.json",
                [[candidate], [provenance]],
            )
            with self.assertRaises(MediaCandidateError):
                compile_media_plan(
                    baseline,
                    [ExplicitMediaBinding("demo.figure", MEMBER, candidate)],
                    analysis_manifest_path=split_manifest,
                )

    def test_manifest_bound_provenance_requires_full_unreduced_equal_counts(self) -> None:
        cases = [
            ("capped", {"sampling_mode": "capped"}),
            ("reduced", {"reduction_applied": True}),
            ("count_mismatch", {"plotted_finite_count": 9}),
            ("missing_series", {"series": []}),
            ("wrong_file_stub", {"file_stub": "stale_candidate"}),
            (
                "one_of_multiple_series_capped",
                {
                    "series": [
                        {
                            "sampling_mode": "full",
                            "reduction_applied": False,
                            "finite_count": 10,
                            "plotted_finite_count": 10,
                        },
                        {
                            "sampling_mode": "capped",
                            "reduction_applied": False,
                            "finite_count": 10,
                            "plotted_finite_count": 10,
                        },
                    ]
                },
            ),
        ]
        for label, overrides in cases:
            with self.subTest(label=label), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                baseline = create_minimal_docx(root / "baseline.docx")
                candidate = write_png(root / "candidate.png", "blue")
                provenance_kwargs = {
                    key: value
                    for key, value in overrides.items()
                    if key in {
                        "sampling_mode",
                        "reduction_applied",
                        "finite_count",
                        "plotted_finite_count",
                        "series",
                        "file_stub",
                    }
                }
                provenance = write_plot_provenance(candidate, **provenance_kwargs)
                manifest = write_analysis_manifest(
                    root / "analysis_manifest.json",
                    [[candidate, provenance]],
                )

                with self.assertRaises(MediaCandidateError):
                    compile_media_plan(
                        baseline,
                        [ExplicitMediaBinding("demo.figure", MEMBER, candidate)],
                        analysis_manifest_path=manifest,
                    )

    def test_manifest_bound_provenance_accepts_audited_v2_render_only_reduction(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            baseline = create_minimal_docx(root / "baseline.docx")
            candidate = write_png(root / "candidate.png", "blue")
            provenance = write_reduced_v2_provenance(candidate)
            manifest = write_analysis_manifest(
                root / "analysis_manifest.json",
                [[candidate, provenance]],
            )

            plan = compile_media_plan(
                baseline,
                [ExplicitMediaBinding("demo.figure", MEMBER, candidate)],
                analysis_manifest_path=manifest,
            )

            apply_media_plan(plan, root / "output.docx")
            self.assertTrue((root / "output.docx").is_file())

    def test_manifest_bound_v2_render_reduction_fails_closed_for_unsafe_variants(self) -> None:
        cases: list[tuple[str, int, dict[str, object], str]] = [
            ("legacy_schema", 1, {}, "schema_version"),
            ("series_legacy_schema", 2, {"schema_version": 1}, "schema_version"),
            (
                "derived_render_mode",
                2,
                {"render_mode": "derived_10min_mean"},
                "without reduction",
            ),
            ("not_render_only", 2, {"reduction_scope": "analysis"}, "render_only"),
            ("unknown_algorithm", 2, {"reduction_algorithm": "lttb"}, "unsupported"),
            ("extrema_not_preserved", 2, {"extrema_preserved": False}, "preserve extrema"),
            ("endpoints_not_preserved", 2, {"first_last_preserved": False}, "first/last"),
            ("render_count_mismatch", 2, {"render_vertex_count": 5}, "render/plotted"),
            ("render_count_exceeds_finite", 2, {
                "plotted_finite_count": 11,
                "render_vertex_count": 11,
            }, "exceeds"),
            ("missing_source", 2, {"source": None}, "source object"),
            ("source_input_mismatch", 2, {
                "source": valid_source_provenance(source_sample_count=11),
            }, "source/input counts differ"),
        ]
        for label, schema_version, overrides, expected in cases:
            with self.subTest(label=label), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                baseline = create_minimal_docx(root / "baseline.docx")
                candidate = write_png(root / "candidate.png", "blue")
                provenance = write_reduced_v2_provenance(
                    candidate,
                    provenance_schema_version=schema_version,
                    **overrides,
                )
                manifest = write_analysis_manifest(
                    root / "analysis_manifest.json",
                    [[candidate, provenance]],
                )

                with self.assertRaisesRegex(MediaCandidateError, expected):
                    compile_media_plan(
                        baseline,
                        [ExplicitMediaBinding("demo.figure", MEMBER, candidate)],
                        analysis_manifest_path=manifest,
                    )

    def test_apply_revalidates_manifest_bound_provenance(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            baseline = create_minimal_docx(root / "baseline.docx")
            candidate = write_png(root / "candidate.png", "blue")
            provenance = write_plot_provenance(candidate)
            manifest = write_analysis_manifest(
                root / "analysis_manifest.json",
                [[candidate, provenance]],
            )
            plan = compile_media_plan(
                baseline,
                [ExplicitMediaBinding("demo.figure", MEMBER, candidate)],
                analysis_manifest_path=manifest,
            )
            write_plot_provenance(candidate, sampling_mode="capped")
            output = root / "output.docx"

            with self.assertRaises(MediaCandidateError):
                apply_media_plan(plan, output)
            self.assertFalse(output.exists())

    def test_source_provenance_gate_rejects_legacy_sidecar(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            baseline = create_minimal_docx(root / "baseline.docx")
            candidate = write_png(root / "candidate.png", "blue")
            provenance = write_plot_provenance(candidate)
            manifest = write_analysis_manifest(
                root / "analysis_manifest.json",
                [[candidate, provenance]],
            )

            with self.assertRaisesRegex(MediaCandidateError, "requires a source object"):
                compile_media_plan(
                    baseline,
                    [
                        ExplicitMediaBinding(
                            "demo.figure",
                            MEMBER,
                            candidate,
                            require_source_provenance=True,
                        )
                    ],
                    analysis_manifest_path=manifest,
                )

    def test_source_provenance_gate_accepts_explicit_incomplete_days_and_round_trips(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            baseline = create_minimal_docx(root / "baseline.docx")
            candidate = write_png(root / "candidate.png", "blue")
            provenance = write_plot_provenance(
                candidate,
                source=valid_source_provenance(),
            )
            manifest = write_analysis_manifest(
                root / "analysis_manifest.json",
                [[candidate, provenance]],
            )
            plan = compile_media_plan(
                baseline,
                [
                    ExplicitMediaBinding(
                        "demo.figure",
                        MEMBER,
                        candidate,
                        require_source_provenance=True,
                    )
                ],
                analysis_manifest_path=manifest,
            )

            loaded = load_media_plan(write_media_plan(plan, root / "plan.json"))
            self.assertTrue(loaded.replacements[0].require_source_provenance)
            self.assertEqual(media_plan_to_dict(loaded), media_plan_to_dict(plan))
            apply_media_plan(loaded, root / "output.docx")

    def test_source_provenance_gate_validates_counts_and_list_fields(self) -> None:
        cases = [
            ("non_numeric_samples", {"source_sample_count": "10"}),
            ("negative_finite_samples", {"finite_source_sample_count": -1}),
            ("finite_exceeds_total", {"finite_source_sample_count": 11}),
            ("missing_completeness_scope", {"completeness_scope": ""}),
            ("unassessed_flag_not_bool", {"internal_gap_coverage_assessed": "false"}),
            ("inconsistent_day_counts", {"calendar_day_count_requested": 3}),
            ("non_integer_day_count", {"complete_day_count": 0.5}),
            ("incomplete_days_not_list", {"incomplete_days": "2026-04-02"}),
            ("incomplete_days_count_mismatch", {"incomplete_days": []}),
            ("missing_sources_not_list", {"missing_required_sources": "2026-04-03"}),
            ("missing_sources_non_string", {"missing_required_sources": [3]}),
        ]
        for label, overrides in cases:
            with self.subTest(label=label), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                baseline = create_minimal_docx(root / "baseline.docx")
                candidate = write_png(root / "candidate.png", "blue")
                write_plot_provenance(
                    candidate,
                    source=valid_source_provenance(**overrides),
                )

                with self.assertRaises(MediaCandidateError):
                    compile_media_plan(
                        baseline,
                        [
                            ExplicitMediaBinding(
                                "demo.figure",
                                MEMBER,
                                candidate,
                                require_source_provenance=True,
                            )
                        ],
                    )

    def test_source_provenance_gate_rejects_source_to_plot_count_mismatches(self) -> None:
        cases = [
            ("source_input_mismatch", {"source_sample_count": 11}),
            ("finite_source_input_mismatch", {"finite_source_sample_count": 9}),
        ]
        for label, source_overrides in cases:
            with self.subTest(label=label), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                baseline = create_minimal_docx(root / "baseline.docx")
                candidate = write_png(root / "candidate.png", "blue")
                write_plot_provenance(
                    candidate,
                    source=valid_source_provenance(**source_overrides),
                )

                with self.assertRaisesRegex(MediaCandidateError, "counts differ"):
                    compile_media_plan(
                        baseline,
                        [
                            ExplicitMediaBinding(
                                "demo.figure",
                                MEMBER,
                                candidate,
                                require_source_provenance=True,
                            )
                        ],
                    )

    def test_apply_uses_pinned_source_provenance_flag(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            baseline = create_minimal_docx(root / "baseline.docx")
            candidate = write_png(root / "candidate.png", "blue")
            provenance = write_plot_provenance(
                candidate,
                source=valid_source_provenance(),
            )
            plan_path = write_media_plan(
                compile_media_plan(
                    baseline,
                    [
                        ExplicitMediaBinding(
                            "demo.figure",
                            MEMBER,
                            candidate,
                            require_source_provenance=True,
                        )
                    ],
                ),
                root / "plan.json",
            )

            write_plot_provenance(candidate)
            payload = json.loads(plan_path.read_text(encoding="utf-8"))
            payload["replacements"][0]["provenance_sha256"] = sha256_file(provenance)
            plan_path.write_text(json.dumps(payload), encoding="utf-8")

            with self.assertRaisesRegex(MediaCandidateError, "requires a source object"):
                apply_media_plan(load_media_plan(plan_path), root / "output.docx")

    def test_require_source_provenance_binding_flag_must_be_boolean(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            candidate = write_png(root / "candidate.png", "blue")
            bindings_path = root / "bindings.json"
            bindings_path.write_text(
                json.dumps(
                    {
                        "bindings": [
                            {
                                "slot_id": "demo.figure",
                                "member": MEMBER,
                                "candidate_path": str(candidate),
                                "require_source_provenance": "true",
                            }
                        ]
                    }
                ),
                encoding="utf-8",
            )

            with self.assertRaises(MediaPlanError):
                load_explicit_bindings(bindings_path)


if __name__ == "__main__":
    unittest.main()
