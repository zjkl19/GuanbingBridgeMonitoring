from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from zipfile import ZipFile


REPO_ROOT = Path(__file__).resolve().parents[1]
REPORTING_ROOT = REPO_ROOT / "reporting"
TESTS_ROOT = Path(__file__).resolve().parent
for candidate in (REPORTING_ROOT, TESTS_ROOT):
    if str(candidate) not in sys.path:
        sys.path.insert(0, str(candidate))

from locked_docx_media import (  # noqa: E402
    BaselineMismatchError,
    IntegrityError,
    MediaCandidateError,
    MediaMemberError,
    OutputExistsError,
    SharedMediaReferenceError,
    apply_media_plan,
    inventory_docx,
    sha256_file,
)
from locked_docx_media_test_utils import create_minimal_docx, write_png  # noqa: E402
from report_media_plan import ExplicitMediaBinding, compile_media_plan  # noqa: E402


MEMBER = "word/media/image1.png"


class LockedDocxMediaTests(unittest.TestCase):
    def _paths(self, root: Path) -> tuple[Path, Path, Path]:
        baseline = create_minimal_docx(root / "baseline.docx")
        candidate = write_png(root / "candidate.png", "blue")
        output = root / "output.docx"
        return baseline, candidate, output

    def _plan(self, baseline: Path, candidate: Path, **kwargs):
        binding = ExplicitMediaBinding(
            slot_id="demo.figure",
            member=MEMBER,
            candidate_path=candidate,
            **kwargs,
        )
        return compile_media_plan(baseline, [binding])

    def test_apply_changes_only_approved_media_member(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            baseline, candidate, output = self._paths(root)
            plan = self._plan(baseline, candidate)

            audit = apply_media_plan(plan, output)

            self.assertTrue(output.exists())
            self.assertEqual(audit.replaced_members, (MEMBER,))
            self.assertEqual(audit.changed_members, (MEMBER,))
            with ZipFile(baseline) as baseline_zip, ZipFile(output) as output_zip:
                self.assertEqual(baseline_zip.namelist(), output_zip.namelist())
                self.assertEqual(output_zip.read(MEMBER), candidate.read_bytes())
                for member in baseline_zip.namelist():
                    if member != MEMBER:
                        self.assertEqual(
                            baseline_zip.read(member),
                            output_zip.read(member),
                            member,
                        )
                self.assertEqual(
                    baseline_zip.read("word/document.xml"),
                    output_zip.read("word/document.xml"),
                )

    def test_wrong_baseline_hash_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            baseline, candidate, _ = self._paths(root)
            with self.assertRaises(BaselineMismatchError):
                compile_media_plan(
                    baseline,
                    [ExplicitMediaBinding("demo.figure", MEMBER, candidate)],
                    expected_baseline_sha256="0" * 64,
                )

    def test_missing_member_and_wrong_member_hash_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            baseline, candidate, _ = self._paths(root)
            with self.assertRaises(MediaMemberError):
                compile_media_plan(
                    baseline,
                    [ExplicitMediaBinding("missing", "word/media/image2.png", candidate)],
                )
            with self.assertRaises(MediaMemberError):
                self._plan(
                    baseline,
                    candidate,
                    expected_original_sha256="f" * 64,
                )

    def test_wrong_candidate_hash_and_dimensions_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            baseline, candidate, _ = self._paths(root)
            with self.assertRaises(MediaCandidateError):
                self._plan(
                    baseline,
                    candidate,
                    expected_candidate_sha256="e" * 64,
                )

            wrong_size = write_png(root / "wrong-size.png", "blue", (21, 10))
            with self.assertRaises(MediaCandidateError):
                self._plan(baseline, wrong_size)

    def test_shared_media_reference_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            baseline = create_minimal_docx(root / "shared.docx", shared_reference=True)
            candidate = write_png(root / "candidate.png", "blue")
            inventory = inventory_docx(baseline)
            self.assertEqual(inventory.media[MEMBER].reference_count, 2)

            with self.assertRaises(SharedMediaReferenceError):
                self._plan(baseline, candidate)

    def test_candidate_change_after_plan_is_rejected_before_output(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            baseline, candidate, output = self._paths(root)
            plan = self._plan(baseline, candidate)
            write_png(candidate, "green")

            with self.assertRaises(MediaCandidateError):
                apply_media_plan(plan, output)
            self.assertFalse(output.exists())

    def test_baseline_change_after_plan_is_rejected_before_output(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            baseline, candidate, output = self._paths(root)
            plan = self._plan(baseline, candidate)
            with ZipFile(baseline, "a") as zf:
                zf.writestr("word/custom.xml", b"changed")

            with self.assertRaises(BaselineMismatchError):
                apply_media_plan(plan, output)
            self.assertFalse(output.exists())

    def test_failed_integrity_check_leaves_no_partial_output(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            baseline, candidate, output = self._paths(root)
            plan = self._plan(baseline, candidate)

            with patch(
                "locked_docx_media.verify_media_only_change",
                side_effect=IntegrityError("forced verification failure"),
            ):
                with self.assertRaises(IntegrityError):
                    apply_media_plan(plan, output)

            self.assertFalse(output.exists())
            self.assertEqual(list(root.glob(f".{output.name}.*.tmp")), [])

    def test_existing_output_is_not_overwritten_without_explicit_flag(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            baseline, candidate, output = self._paths(root)
            plan = self._plan(baseline, candidate)
            output.write_bytes(b"keep me")

            with self.assertRaises(OutputExistsError):
                apply_media_plan(plan, output)

            self.assertEqual(output.read_bytes(), b"keep me")
            self.assertNotEqual(sha256_file(output), plan.baseline_sha256)


if __name__ == "__main__":
    unittest.main()
