import sys
import os
import tempfile
import time
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "reporting"))

from artifact_lookup import (  # noqa: E402
    filename_has_point_token,
    latest_file_patterns,
    latest_point_image_patterns,
    resolve_output_dirs,
)


class TestArtifactLookup(unittest.TestCase):
    def test_point_token_does_not_match_prefix_collision(self):
        self.assertTrue(filename_has_point_token(Path("CS1_time.jpg"), "CS1"))
        self.assertFalse(filename_has_point_token(Path("CS12_time.jpg"), "CS1"))

    def test_latest_point_image_uses_strict_point_token_for_filesystem(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            folder = root / "figs"
            folder.mkdir()
            wrong = folder / "CS12_time.jpg"
            right = folder / "CS1_time.jpg"
            wrong.write_text("wrong", encoding="utf-8")
            right.write_text("right", encoding="utf-8")
            result = latest_point_image_patterns(root, "figs", "CS1", ["CS1*.jpg", "CS12*.jpg"])
            self.assertEqual(result.path, right.resolve())
            self.assertTrue(result.debug["rejected_prefix_collisions"])

    def test_latest_file_patterns_prefers_manifest_when_available(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            folder = root / "时程曲线_加速度"
            folder.mkdir()
            old = folder / "A1_old.jpg"
            new = folder / "A1_new.jpg"
            old.write_text("old", encoding="utf-8")
            new.write_text("new", encoding="utf-8")
            now = time.time()
            os.utime(old, (now - 10, now - 10))
            os.utime(new, (now, now))
            run_logs = root / "run_logs"
            run_logs.mkdir()
            manifest = {
                "schema_version": 2,
                "module_results": [
                    {
                        "key": "acceleration",
                        "artifacts": [
                            {"kind": "figure", "role": "time_history", "path": str(old)},
                            {"kind": "figure", "role": "time_history", "path": str(new)},
                        ],
                    }
                ],
            }
            (run_logs / "analysis_manifest_1.json").write_text(__import__("json").dumps(manifest), encoding="utf-8")
            result = latest_file_patterns(root, "时程曲线_加速度", ["A1*.jpg"], kind=None)
            self.assertEqual(result.path, new)
            self.assertEqual(result.debug["source"], "analysis_manifest")

    def test_resolve_output_dirs_skips_venv_when_recursive(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            good = root / "a" / "plots"
            bad = root / ".venv" / "plots"
            good.mkdir(parents=True)
            bad.mkdir(parents=True)
            dirs = resolve_output_dirs(root, "plots")
            self.assertIn(good.resolve(), dirs)
            self.assertNotIn(bad.resolve(), dirs)


if __name__ == "__main__":
    unittest.main()
