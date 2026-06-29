import unittest
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "reporting"))

from bridge_profiles import load_profiles, profile_by_id  # noqa: E402
from report_module_catalog import expected_stats_files  # noqa: E402


class BridgeProfilesTest(unittest.TestCase):
    def test_loads_known_profiles(self):
        root = Path(__file__).resolve().parents[1]
        profiles = load_profiles(root)
        ids = {profile.bridge_id for profile in profiles}

        self.assertIn("guanbing", ids)
        self.assertIn("hongtang", ids)
        self.assertIn("jiulongjiang", ids)

        hongtang = profile_by_id(profiles, "hongtang")
        self.assertEqual(hongtang.report_gui_type, "hongtang_period_wim")
        self.assertTrue(str(hongtang.wim_root_for(Path(r"E:\洪塘大桥数据\2026年1-3月"))).endswith(r"WIM\results\hongtang"))

    def test_profile_modules_drive_report_stats_expectations(self):
        root = Path(__file__).resolve().parents[1]
        profiles = load_profiles(root)

        jlj = profile_by_id(profiles, "jiulongjiang")
        stats = expected_stats_files(jlj.enabled_modules)

        self.assertIn("bearing_displacement_stats.xlsx", stats)
        self.assertIn("accel_spec_stats.xlsx", stats)
        self.assertIn("strain_stats.xlsx", stats)
        self.assertTrue(jlj.report_template.endswith("九龙江大桥健康监测2026年3月份月报_0508.docx"))


if __name__ == "__main__":
    unittest.main()
