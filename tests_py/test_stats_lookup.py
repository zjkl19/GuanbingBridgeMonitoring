import json
import hashlib
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "reporting"))

from stats_lookup import manifest_search_root, resolve_from_analysis_manifest, stats_key_for_filename  # noqa: E402
from analysis_manifest import pinned_analysis_manifest_scope  # noqa: E402


class TestStatsLookup(unittest.TestCase):
    def test_strict_pinned_manifest_disables_latest_and_filesystem_fallback(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            stats = root / "stats"
            stats.mkdir()
            pinned_stats = stats / "accel_stats.xlsx"
            fallback_stats = root / "accel_stats.xlsx"
            pinned_stats.write_text("pinned", encoding="utf-8")
            fallback_stats.write_text("fallback", encoding="utf-8")
            manifest = root / "analysis_manifest.json"
            manifest.write_text(json.dumps({
                "module_results": [{
                    "key": "acceleration",
                    "stats_path": str(pinned_stats),
                    "artifacts": [{
                        "kind": "stats",
                        "role": "stats",
                        "path": str(pinned_stats),
                        "exists": True,
                        "bytes": pinned_stats.stat().st_size,
                        "sha256": hashlib.sha256(pinned_stats.read_bytes()).hexdigest().upper(),
                    }],
                }],
            }), encoding="utf-8")
            manifest_hash = hashlib.sha256(manifest.read_bytes()).hexdigest().upper()

            with pinned_analysis_manifest_scope(
                manifest,
                manifest_hash,
                require_source_provenance=True,
                result_root=root,
            ):
                self.assertEqual(
                    resolve_from_analysis_manifest(root, root, "accel_stats.xlsx"),
                    pinned_stats,
                )
                with self.assertRaisesRegex(FileNotFoundError, "pinned analysis manifest"):
                    resolve_from_analysis_manifest(root, root, "wind_stats.xlsx")

    def test_stats_key_for_filename(self):
        self.assertEqual(stats_key_for_filename("accel_stats.xlsx"), "acceleration")
        self.assertIsNone(stats_key_for_filename("unknown.xlsx"))

    def test_manifest_search_root_uses_stats_parent(self):
        self.assertEqual(manifest_search_root(Path("E:/data/stats")), Path("E:/data"))
        self.assertEqual(manifest_search_root(Path("E:/data")), Path("E:/data"))

    def test_resolve_from_analysis_manifest_prefers_manifest_stats_path(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            stats = root / "stats"
            logs = root / "run_logs"
            stats.mkdir()
            logs.mkdir()
            stats_file = stats / "accel_stats.xlsx"
            stats_file.write_text("x", encoding="utf-8")
            manifest = {
                "schema_version": 2,
                "module_results": [
                    {"key": "acceleration", "stats_path": str(stats_file), "artifacts": []}
                ],
            }
            (logs / "analysis_manifest_1.json").write_text(json.dumps(manifest), encoding="utf-8")
            self.assertEqual(resolve_from_analysis_manifest(stats, None, "accel_stats.xlsx"), stats_file)


if __name__ == "__main__":
    unittest.main()
