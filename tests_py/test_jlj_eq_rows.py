from __future__ import annotations

import csv
import tempfile
import unittest
from pathlib import Path
import sys

from openpyxl import Workbook

REPO_ROOT = Path(__file__).resolve().parents[1]
REPORTING_ROOT = REPO_ROOT / "reporting"
for candidate in (REPO_ROOT, REPORTING_ROOT):
    if str(candidate) not in sys.path:
        sys.path.insert(0, str(candidate))

from reporting.build_jlj_monthly_report import collect_eq_peak_rows, load_eq_peak_rows_from_stats


class JiulongjiangEarthquakeRowsTests(unittest.TestCase):
    def test_load_eq_peak_rows_from_stats_normalizes_component_suffix(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            stats_dir = root / "stats"
            stats_dir.mkdir()
            workbook = Workbook()
            sheet = workbook.active
            sheet.append(["PointID", "Peak", "PeakTime"])
            sheet.append(["DZY-01-D15-P15-X", -0.2345, "2026-03-23 00:00:01"])
            workbook.save(stats_dir / "eq_stats.xlsx")

            rows = load_eq_peak_rows_from_stats(root)

            self.assertEqual(
                rows,
                [
                    {
                        "PointID": "DZY-01-D15-P15",
                        "Component": "X",
                        "Peak": 0.2345,
                        "PeakTime": "2026-03-23 00:00:01",
                    }
                ],
            )

    def test_collect_eq_peak_rows_uses_stats_before_raw_csv(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            stats_dir = root / "stats"
            stats_dir.mkdir()
            workbook = Workbook()
            sheet = workbook.active
            sheet.append(["PointID", "Component", "Peak", "PeakTime"])
            sheet.append(["DZY-01-D15-P15", "Y", 0.456, "2026-03-24 00:00:00"])
            workbook.save(stats_dir / "eq_stats.xlsx")

            csv_dir = root / "data_jlj_2026-03-24" / "data" / "jlj" / "csv"
            csv_dir.mkdir(parents=True)
            with (csv_dir / "DZY-01-D15-P15.csv").open("w", newline="", encoding="utf-8") as fh:
                writer = csv.DictWriter(fh, fieldnames=["ts", "value_x", "value_y", "value_z"])
                writer.writeheader()
                writer.writerow({"ts": "2026-03-24 00:00:01", "value_x": 99, "value_y": 99, "value_z": 99})

            rows = collect_eq_peak_rows(root, root, max_raw_scan_bytes=0)

            self.assertEqual(len(rows), 1)
            self.assertEqual(rows[0]["Component"], "Y")
            self.assertEqual(rows[0]["Peak"], 0.456)

    def test_collect_eq_peak_rows_skips_large_raw_fallback(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            csv_dir = root / "data_jlj_2026-03-24" / "data" / "jlj" / "csv"
            csv_dir.mkdir(parents=True)
            path = csv_dir / "DZY-01-D15-P15.csv"
            path.write_text("ts,value_x,value_y,value_z\n2026-03-24 00:00:01,1,2,3\n", encoding="utf-8")

            rows = collect_eq_peak_rows(root, max_raw_scan_bytes=1)

            self.assertEqual(rows, [])


if __name__ == "__main__":
    unittest.main()
