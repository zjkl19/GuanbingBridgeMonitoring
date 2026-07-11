import sys
import tempfile
import unittest
from pathlib import Path

from docx import Document


ROOT = Path(__file__).resolve().parents[1]
REPORTING = ROOT / "reporting"
if str(REPORTING) not in sys.path:
    sys.path.insert(0, str(REPORTING))

from build_zhishan_monthly_report import (  # noqa: E402
    RangeStats,
    lowpass_alarm_note,
    update_data_availability,
)


class ZhishanReportGeneratorTests(unittest.TestCase):
    def test_lowpass_alarm_note_uses_configured_point_bound(self) -> None:
        context = {
            "dynamic_lp_point_stats": {
                "SX-5": RangeStats(min_value=317.1, max_value=999.9),
                "SX-6": RangeStats(min_value=-15.4, max_value=54.9),
            },
            "strain_alarm_bounds": {
                "SX-5": (-252.0, 405.0),
                "SX-6": (-252.0, 405.0),
            },
        }

        note = lowpass_alarm_note(context)

        self.assertIn("SX-5", note)
        self.assertIn("999.9με", note)
        self.assertIn("+405.0με", note)
        self.assertIn("不宜仅据此直接判定为结构异常", note)
        self.assertNotIn("SX-6", note)

    def test_source_quality_note_is_written_to_coverage_text(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result_root = Path(tmp)
            (result_root / "2026-06-01").mkdir()
            doc = Document()
            doc.add_paragraph("本月报告分析数据覆盖旧内容")
            doc.add_paragraph("按本月监测数据获取情况表统计旧内容")
            doc.add_paragraph("本月持续开展监测系统运行维护工作旧内容")
            doc.add_paragraph("软件线上检查维护旧内容")
            note = (
                "源数据完整性说明：缺少2026-07-01相邻滚动文件，"
                "6月30日尾段不完整；仅使用实际获取数据，不作伪造补齐。"
            )

            update_data_availability(
                doc,
                result_root,
                "2026年6月",
                "2026年6月1日~2026年6月30日",
                note,
            )

            text = "\n".join(paragraph.text for paragraph in doc.paragraphs)
            self.assertIn(note, text)
            self.assertIn("实际有效数据为1天", text)


if __name__ == "__main__":
    unittest.main()
