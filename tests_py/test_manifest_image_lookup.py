import sys
import os
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "reporting"))

from analysis_manifest import manifest_key_for_dir, manifest_latest_artifact, manifest_role_for_lookup  # noqa: E402


class TestManifestImageLookup(unittest.TestCase):
    def test_key_mapping_and_latest_artifact(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            old = root / "time_dir" / "A1_old.jpg"
            new = root / "time_dir" / "A1_new.jpg"
            new.parent.mkdir(parents=True)
            old.write_text("old", encoding="utf-8")
            new.write_text("new", encoding="utf-8")
            os.utime(old, (1000, 1000))
            os.utime(new, (2000, 2000))
            manifest = {
                "module_results": [
                    {
                        "key": "acceleration",
                        "artifacts": [
                            {"kind": "figure", "role": "time_history", "path": str(old)},
                            {"kind": "figure", "role": "time_history", "path": str(new)},
                        ],
                    }
                ]
            }

            self.assertEqual(manifest_key_for_dir("\u65f6\u7a0b\u66f2\u7ebf_\u52a0\u901f\u5ea6_RMS10min"), "acceleration")
            self.assertEqual(
                manifest_latest_artifact(
                    manifest,
                    "acceleration",
                    token="A1",
                    suffixes=(".jpg",),
                    directory_hint="time_dir",
                ),
                new,
            )


    def test_directory_hint_is_exact_suffix(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            raw = root / "time_accel" / "A1_plot.jpg"
            rms = root / "time_accel_RMS10min" / "A1_plot.jpg"
            raw.parent.mkdir(parents=True)
            rms.parent.mkdir(parents=True)
            raw.write_text("raw", encoding="utf-8")
            rms.write_text("rms", encoding="utf-8")
            os.utime(raw, (1000, 1000))
            os.utime(rms, (2000, 2000))
            manifest = {
                "module_results": [
                    {
                        "key": "acceleration",
                        "artifacts": [
                            {"kind": "figure", "role": "raw", "path": str(raw)},
                            {"kind": "figure", "role": "rms10min", "path": str(rms)},
                        ],
                    }
                ]
            }

            self.assertEqual(
                manifest_latest_artifact(
                    manifest,
                    "acceleration",
                    token="A1",
                    suffixes=(".jpg",),
                    directory_hint="time_accel",
                ),
                raw,
            )

    def test_unknown_dir_returns_none(self):
        self.assertIsNone(manifest_key_for_dir("unknown"))
        self.assertIsNone(manifest_latest_artifact({}, None, token="A1"))

    def test_deflection_raw_filtered_roles_are_explicit(self):
        self.assertEqual(manifest_key_for_dir("时程曲线_挠度_原始"), "deflection")
        self.assertEqual(manifest_key_for_dir("时程曲线_挠度_滤波"), "deflection")
        self.assertEqual(manifest_role_for_lookup("时程曲线_挠度_原始", "Defl_D1_Orig"), "raw")
        self.assertEqual(manifest_role_for_lookup("时程曲线_挠度_滤波", "Defl_D1_Filt"), "filtered")


if __name__ == "__main__":
    unittest.main()
