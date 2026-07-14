import os
import shutil
import sys
import unittest
from unittest.mock import patch
from datetime import date
from pathlib import Path

from docx import Document
from docx.opc.constants import RELATIONSHIP_TYPE as RT
from docx.oxml.ns import qn
from openpyxl import Workbook

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "reporting"))

from artifact_lookup import ArtifactLookupResult  # noqa: E402
from build_jlj_monthly_report import (  # noqa: E402
    build_report,
    build_wind_section,
    clean_jlj_report_xml_text,
    collect_jlj_data_acquisition_rows,
    find_latest_two_deflection_images,
    find_latest_point_image_patterns,
    find_wind_summary_file,
    jlj_image_matches_report_period,
    jlj_report_period_scope,
    normalize_cover_monitoring_time,
    read_stats_rows,
    update_jlj_warning_threshold_table,
    validate_jlj_analysis_period,
)


class TestJljReportGenerator(unittest.TestCase):
    def setUp(self):
        self.tmp = Path("tmp") / "test_jlj_report_generator"
        shutil.rmtree(self.tmp, ignore_errors=True)
        self.tmp.mkdir(parents=True)

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_cover_monitoring_time_uses_report_month(self):
        self.assertEqual(
            normalize_cover_monitoring_time("2026年3月份", "2026.03.23~2026.03.31"),
            "2026年3月",
        )
        self.assertEqual(
            normalize_cover_monitoring_time("", "2026.03.23~2026.03.31"),
            "2026年3月",
        )

    def test_data_acquisition_includes_pending_expansion_joint_points(self):
        rows = collect_jlj_data_acquisition_rows({}, self.tmp, date(2026, 3, 23), date(2026, 3, 31))
        expansion_rows = [row for row in rows if row["module"] == "伸缩缝位移监测"]

        self.assertEqual(len(expansion_rows), 1)
        row = expansion_rows[0]
        self.assertEqual(row["design_count"], "4")
        self.assertEqual(row["acquired_count"], "0")
        self.assertEqual(row["rate"], "0.0%")
        self.assertEqual(row["date_range"], "/")
        self.assertIn("新版竣工图新增测点SSFWYJ-01~04", row["remarks"])

    def test_warning_threshold_table_fixed_text_and_arch_lower_bound(self):
        doc = Document()
        table = doc.add_table(rows=4, cols=6)
        for col_idx, value in enumerate(["报警类别", "监测项", "报警规则", "统计值", "上限", "下限"]):
            table.cell(0, col_idx).text = value
        table.cell(1, 1).text = "主梁跨中静应变"
        table.cell(1, 2).text = "超过设计值"
        table.cell(2, 1).text = "主拱拱顶静应变"
        table.cell(2, 2).text = "超过设计值"
        table.cell(3, 1).text = "拱桥主拱拱顶位移"
        table.cell(3, 2).text = "超过0.8倍设计值"
        table.cell(3, 5).text = "-57.4mm"

        update_jlj_warning_threshold_table(doc)

        self.assertEqual(table.cell(3, 5).text, "-59.4mm")
        self.assertIn("MPa", table.cell(1, 4).text)
        self.assertIn("με", table.cell(2, 5).text)

    def test_cleanup_normalizes_accepted_report_text_typos(self):
        path = self.tmp / "cleanup.docx"
        doc = Document()
        doc.add_paragraph("10min加速度速度均方根；桥墩沉降°；DYBCQG-24-K16-ZGD-A20。")
        doc.save(path)

        clean_jlj_report_xml_text(path)

        cleaned = "\n".join(p.text for p in Document(path).paragraphs)
        self.assertIn("10min加速度均方根", cleaned)
        self.assertIn("桥墩沉降", cleaned)
        self.assertIn("DYBCGQ-24-K16-ZGD-A20", cleaned)
        self.assertNotIn("DYBCQG", cleaned)

    def test_missing_optional_stats_returns_empty_rows(self):
        rows = read_stats_rows(self.tmp / "stats", "strain_stats.xlsx", self.tmp)
        self.assertEqual(rows, [])

    def test_deflection_images_use_split_raw_filtered_dirs(self):
        raw_dir = self.tmp / "时程曲线_挠度_原始"
        filt_dir = self.tmp / "时程曲线_挠度_滤波"
        raw_dir.mkdir()
        filt_dir.mkdir()
        raw = raw_dir / "Defl_NDY-01_Orig_20260301_20260331.jpg"
        filt = filt_dir / "Defl_NDY-01_Filt_20260301_20260331.jpg"
        raw.write_bytes(b"raw")
        filt.write_bytes(b"filt")

        self.assertEqual(find_latest_two_deflection_images(self.tmp, "NDY-01"), (raw.resolve(), filt.resolve()))

    def test_period_filter_prefers_current_month_over_newer_stale_file(self):
        folder = self.tmp / "figures"
        folder.mkdir()
        stale = folder / "P-01_20260301_20260331.jpg"
        current = folder / "P-01_20260501_20260531.jpg"
        stale.write_bytes(b"stale")
        current.write_bytes(b"current")
        os.utime(current, (1, 1))
        os.utime(stale, (2, 2))

        with jlj_report_period_scope(date(2026, 5, 1), date(2026, 5, 31)):
            selected = find_latest_point_image_patterns(
                self.tmp,
                "figures",
                "P-01",
                ["P-01_*.jpg"],
            )

        self.assertEqual(selected, current.resolve())
        self.assertTrue(
            jlj_image_matches_report_period(current, date(2026, 5, 1), date(2026, 5, 31))
        )
        self.assertFalse(
            jlj_image_matches_report_period(stale, date(2026, 5, 1), date(2026, 5, 31))
        )

    def test_analysis_manifest_period_mismatch_is_blocked(self):
        context = {
            "available": True,
            "path": "analysis_manifest_march.json",
            "run_request": {"start_date": "2026-03-23", "end_date": "2026-03-31"},
        }
        with self.assertRaisesRegex(ValueError, "manifest period does not match"):
            validate_jlj_analysis_period(context, date(2026, 5, 1), date(2026, 5, 31))

    def test_wind_summary_prefers_requested_period_and_rejects_stale_only(self):
        folder = self.tmp / "wind"
        folder.mkdir()
        stale = folder / "W1_windrose_2026-03-01_2026-03-31_summary.txt"
        current = folder / "W1_windrose_2026-05-01_2026-05-31_summary.txt"
        stale.write_text("stale", encoding="utf-8")
        current.write_text("current", encoding="utf-8")
        os.utime(current, (1, 1))
        os.utime(stale, (2, 2))

        with jlj_report_period_scope(date(2026, 5, 1), date(2026, 5, 31)):
            self.assertEqual(find_wind_summary_file(self.tmp, "wind", "W1"), current.resolve())
            current.unlink()
            with self.assertRaisesRegex(ValueError, "do not match the requested report period"):
                find_wind_summary_file(self.tmp, "wind", "W1")

    def test_wind_summary_rejects_wrong_period_manifest_record(self):
        stale = self.tmp / "W1_windrose_2026-03-01_2026-03-31_summary.txt"
        stale.write_text("stale", encoding="utf-8")
        lookup = ArtifactLookupResult(
            stale,
            {
                "source": "analysis_manifest",
                "manifest": "analysis_run_manifest.json",
            },
        )
        with patch("build_jlj_monthly_report.lookup_latest_file_patterns", return_value=lookup):
            with jlj_report_period_scope(date(2026, 5, 1), date(2026, 5, 31)):
                with self.assertRaisesRegex(ValueError, "bound analysis manifest period"):
                    find_wind_summary_file(self.tmp, "wind", "W1")

    def test_wind_narrative_explicitly_reports_bridge_deck_point(self):
        stats = self.tmp / "stats"
        stats.mkdir()
        workbook = Workbook()
        sheet = workbook.active
        sheet.append(["PointID", "Mean10minMax", "Mean10minTime"])
        sheet.append(["CSFSY-01-K16-GD-A20", 17.69, "2026-03-30 16:20:33"])
        sheet.append(["CSFSY-02-K16-QM-G20", 14.72, "2026-03-25 15:47:53"])
        workbook.save(stats / "wind_stats.xlsx")

        summary_dir = self.tmp / "风速风向结果" / "风玫瑰"
        summary_dir.mkdir(parents=True)
        for point_id in ("CSFSY-01-K16-GD-A20", "CSFSY-02-K16-QM-G20"):
            (summary_dir / f"{point_id}_windrose_2026-03-23_2026-03-31_summary.txt").write_text(
                "平均风速: 1.00 m/s\n最大风速: 2.00 m/s\n主导风向: 292.5°-315.0°\n主要风速等级: 0-2 m/s",
                encoding="utf-8",
            )

        with jlj_report_period_scope(date(2026, 3, 23), date(2026, 3, 31)):
            section = build_wind_section({}, self.tmp, stats, None, self.tmp)

        self.assertIn("主桥桥面10min平均风速最大值为14.72m/s", section.narrative)
        self.assertNotIn("主桥10min平均风速最大值", section.narrative)

    def test_real_template_future_month_clears_stale_cover_patrol_and_media(self):
        repo_root = Path(__file__).resolve().parents[1]
        template = repo_root / "reports" / "九龙江大桥健康监测2026年3月份月报_0508.docx"
        result_root = self.tmp / "may_result"
        output_dir = self.tmp / "may_report"
        result_root.mkdir()

        template_section_count = len(Document(str(template)).sections)
        output = build_report(
            template=template,
            config_path=repo_root / "config" / "jiulongjiang_config.json",
            result_root=result_root,
            output_dir=output_dir,
            period_label="2026年5月份",
            monitoring_range="2026.05.01~2026.05.31",
            report_date="2026年06月05日",
            precheck_template=True,
            update_word=False,
        )

        doc = Document(str(output))
        text = "\n".join(paragraph.text for paragraph in doc.paragraphs)
        text += "\n" + "\n".join(
            cell.text for table in doc.tables for row in table.rows for cell in row.cells
        )
        self.assertIn("监测时间：2026年5月", text)
        self.assertIn("报告日期：2026年06月05日", text)
        self.assertIn("本期巡查资料未提供", text)
        self.assertNotIn("监测时间：2026年03月", text)
        self.assertNotIn("2026年03月09日上午", text)
        self.assertNotIn("2026年3月份", output.name)
        self.assertEqual(len(doc.sections), template_section_count)
        self.assertEqual(doc.element.body[-1].tag, qn("w:sectPr"))

        used_rel_ids = set(doc.element.body.xpath(".//a:blip/@r:embed"))
        relationship_id_attr = (
            "{http://schemas.openxmlformats.org/officeDocument/2006/relationships}id"
        )
        for element in doc.element.body.iter():
            if str(element.tag).endswith("}imagedata"):
                rel_id = element.get(relationship_id_attr)
                if rel_id:
                    used_rel_ids.add(rel_id)
        image_rel_ids = {
            rel_id
            for rel_id, relationship in doc.part.rels.items()
            if relationship.reltype == RT.IMAGE
        }
        self.assertEqual(image_rel_ids, used_rel_ids)

    def test_report_qc_exception_writes_manifest_then_fails_closed(self):
        repo_root = Path(__file__).resolve().parents[1]
        template = repo_root / "reports" / "九龙江大桥健康监测2026年3月份月报_0508.docx"
        result_root = self.tmp / "qc_failure_result"
        output_dir = self.tmp / "qc_failure_report"
        result_root.mkdir()

        with patch(
            "build_jlj_monthly_report.check_jlj_report",
            side_effect=RuntimeError("synthetic QC crash"),
        ):
            with self.assertRaisesRegex(RuntimeError, "QC execution failed"):
                build_report(
                    template=template,
                    config_path=repo_root / "config" / "jiulongjiang_config.json",
                    result_root=result_root,
                    output_dir=output_dir,
                    period_label="2026年5月份",
                    monitoring_range="2026.05.01~2026.05.31",
                    report_date="2026年06月05日",
                    precheck_template=True,
                    update_word=False,
                )

        manifests = sorted(output_dir.glob("jlj_report_build_manifest_*.json"))
        self.assertTrue(manifests)
        payload = manifests[-1].read_text(encoding="utf-8")
        self.assertIn("report_qc_failed", payload)
        self.assertIn("synthetic QC crash", payload)


if __name__ == "__main__":
    unittest.main()
