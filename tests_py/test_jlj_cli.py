import sys
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "reporting"))

from build_jlj_monthly_report import parse_args  # noqa: E402
from jlj_patrol import resolve_patrol_report_source  # noqa: E402


class TestJljCli(unittest.TestCase):
    def test_direct_script_help_resolves_project_packages(self):
        script = Path(__file__).resolve().parents[1] / "reporting" / "build_jlj_monthly_report.py"
        env = os.environ.copy()
        env.pop("PYTHONPATH", None)
        with tempfile.TemporaryDirectory() as folder:
            completed = subprocess.run(
                [sys.executable, str(script), "--help"],
                cwd=folder,
                env=env,
                capture_output=True,
                text=True,
                timeout=30,
                check=False,
            )
        self.assertEqual(0, completed.returncode, completed.stderr)

    def test_parse_args_accepts_standard_report_parameters(self):
        args = parse_args([
            "--template", "reports/template.docx",
            "--config", "config/bridge.json",
            "--result-root", "E:/data",
            "--output-dir", "E:/data/report",
            "--period-label", "2026年3月份",
            "--monitoring-range", "2026.03.23~2026.03.31",
            "--report-date", "2026年05月08日",
            "--image-root", "E:/data/images",
            "--wim-root", "E:/data/WIM/results",
            "--patrol-docx", "reports/patrol.docx",
            "--skip-template-precheck",
            "--no-word-update",
        ])

        self.assertEqual(args.template, Path("reports/template.docx"))
        self.assertEqual(args.config, Path("config/bridge.json"))
        self.assertEqual(args.result_root, Path("E:/data"))
        self.assertEqual(args.output_dir, Path("E:/data/report"))
        self.assertEqual(args.period_label, "2026年3月份")
        self.assertEqual(args.monitoring_range, "2026.03.23~2026.03.31")
        self.assertEqual(args.report_date, "2026年05月08日")
        self.assertEqual(args.image_root, Path("E:/data/images"))
        self.assertEqual(args.wim_root, Path("E:/data/WIM/results"))
        self.assertEqual(args.patrol_docx, Path("reports/patrol.docx"))
        self.assertTrue(args.skip_template_precheck)
        self.assertTrue(args.no_word_update)

    def test_parse_args_requires_result_root(self):
        with self.assertRaises(SystemExit):
            parse_args([])

    def test_resolve_patrol_report_source_validates_explicit_path(self):
        with self.assertRaises(FileNotFoundError):
            resolve_patrol_report_source(Path("template.docx"), Path("missing_patrol_source.docx"))


if __name__ == "__main__":
    unittest.main()
