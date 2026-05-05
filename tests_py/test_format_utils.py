import sys
import unittest
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "reporting"))

from format_utils import (  # noqa: E402
    format_number,
    format_number_fixed,
    format_percent,
    format_range,
    format_range_fixed,
    format_table_number,
    numeric_max,
    numeric_mean,
    numeric_min,
    parse_float,
    safe_text,
    table_cell_text,
)


class TestFormatUtils(unittest.TestCase):
    def test_parse_float_rejects_empty_and_nan(self):
        self.assertIsNone(parse_float(None))
        self.assertIsNone(parse_float(""))
        self.assertIsNone(parse_float("nan"))
        self.assertEqual(parse_float("1.25"), 1.25)

    def test_number_and_range_formatting(self):
        self.assertEqual(format_number(1.2300, 3, "mm"), "1.23mm")
        self.assertEqual(format_number_fixed(1.2, 3, "mm"), "1.200mm")
        self.assertEqual(format_range(1.2, 3.0, 3, "mm"), "1.2mm~3mm")
        self.assertEqual(format_range_fixed(1.2, 3.0, 1, "mm"), "1.2mm~3.0mm")
        self.assertEqual(format_table_number(None), "/")

    def test_numeric_aggregates(self):
        rows = [{"x": "1"}, {"x": 2.5}, {"x": None}]
        self.assertEqual(numeric_min(rows, "x"), 1.0)
        self.assertEqual(numeric_max(rows, "x"), 2.5)
        self.assertAlmostEqual(numeric_mean(rows, "x"), 1.75)

    def test_text_datetime_and_percent(self):
        dt = datetime(2026, 1, 2, 3, 4, 5)
        self.assertEqual(safe_text(dt), "2026-01-02 03:04:05")
        self.assertEqual(table_cell_text(dt), "2026-01-02 03:04:05")
        self.assertEqual(table_cell_text(1.230000), "1.23")
        self.assertEqual(format_percent(1, 200000), "0.00050")
        self.assertEqual(format_percent(1, 0), "0.00000")


if __name__ == "__main__":
    unittest.main()
