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


if __name__ == "__main__":
    unittest.main()
