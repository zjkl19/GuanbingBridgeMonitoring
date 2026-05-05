import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "reporting"))

from openpyxl import Workbook  # noqa: E402

from excel_utils import load_sheet_rows  # noqa: E402


class TestExcelUtils(unittest.TestCase):
    def test_load_sheet_rows_preserves_default_behavior(self):
        with tempfile.TemporaryDirectory() as td:
            path = Path(td) / "x.xlsx"
            wb = Workbook()
            ws = wb.active
            ws.append([" A ", None])
            ws.append([1, 2])
            wb.save(path)
            rows = load_sheet_rows(path)
            self.assertEqual(rows, [{" A ": 1, "": 2}])

    def test_load_sheet_rows_strips_and_skips_empty(self):
        with tempfile.TemporaryDirectory() as td:
            path = Path(td) / "x.xlsx"
            wb = Workbook()
            ws = wb.active
            ws.append([" A ", None])
            ws.append([None, None])
            ws.append([1, 2])
            wb.save(path)
            rows = load_sheet_rows(path, strip_headers=True, skip_empty=True)
            self.assertEqual(rows, [{"A": 1}])

    def test_load_sheet_rows_missing_optional(self):
        self.assertEqual(load_sheet_rows(Path("not_exists.xlsx"), require_exists=False), [])


if __name__ == "__main__":
    unittest.main()
