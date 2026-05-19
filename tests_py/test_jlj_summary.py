import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "reporting"))

from jlj_summary import build_summary_result_lines, normalize_summary_advice_lines  # noqa: E402


class DummySection:
    def __init__(self, summary_sentence=""):
        self.summary_sentence = summary_sentence


class TestJljSummary(unittest.TestCase):
    def test_placeholder_advice_is_expanded_without_fixed_points(self):
        lines = normalize_summary_advice_lines([
            "针对目前的监测状况，建议如下：",
            "建议数据提供单位提高所提供监测数据的质量，加强对平台运维的管理。",
        ])

        joined = "\n".join(lines)
        self.assertIn("专项排查", joined)
        self.assertIn("明确责任单位和完成时限", joined)
        self.assertNotIn("JGWD-01", joined)

    def test_manual_detailed_advice_is_preserved(self):
        original = ["针对目前的监测状况，建议如下：", "3、建议对以下测点或测项开展专项排查：JGWD-01。"]

        self.assertEqual(normalize_summary_advice_lines(original), original)

    def test_summary_result_lines_include_data_quality_statement(self):
        section_map = {
            key: DummySection("ok")
            for key in [
                "main_env",
                "main_humidity",
                "main_rainfall",
                "main_wind",
                "main_eq",
                "main_traffic",
                "main_deflection",
                "main_bearing",
                "main_gnss",
                "main_vibration",
                "main_strain",
                "main_crack",
                "main_cable",
                "north_strain",
                "north_bearing",
                "north_tilt",
                "south_strain",
                "south_bearing",
                "south_tilt",
            ]
        }

        lines = build_summary_result_lines(section_map)

        self.assertEqual(lines[0], "一、监测系统运行情况")
        self.assertIn("不直接作为结构状态异常判据", lines[1])


if __name__ == "__main__":
    unittest.main()
