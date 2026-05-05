import sys
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "reporting"))

from analysis_manifest import manifest_artifact_paths, manifest_stats_path  # noqa: E402


class TestReportManifestArtifacts(unittest.TestCase):
    def test_manifest_stats_and_artifact_lookup(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            stats = root / "stats.xlsx"
            image = root / "plot.jpg"
            stats.write_text("x", encoding="utf-8")
            image.write_text("x", encoding="utf-8")
            manifest = {
                "module_results": [
                    {
                        "key": "deflection",
                        "stats_path": str(stats),
                        "artifacts": [
                            {"kind": "stats", "path": str(stats)},
                            {"kind": "figure", "path": str(image)},
                        ],
                    }
                ]
            }

            self.assertEqual(manifest_stats_path(manifest, "deflection", "stats.xlsx"), stats)
            self.assertEqual(
                manifest_artifact_paths(manifest, "deflection", kind="figure", suffixes=(".jpg",)),
                [image],
            )


if __name__ == "__main__":
    unittest.main()
