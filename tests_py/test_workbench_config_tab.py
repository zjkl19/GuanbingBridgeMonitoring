from __future__ import annotations

import json
import os
import tempfile
import unittest
from pathlib import Path

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

try:
    from PySide6.QtWidgets import QApplication

    from workbench.config_tab import AlarmBoundsEditorWidget
except ImportError:  # pragma: no cover
    QApplication = None
    AlarmBoundsEditorWidget = None


@unittest.skipIf(QApplication is None, "PySide6 is not installed")
class WorkbenchConfigTabTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.app = QApplication.instance() or QApplication([])

    def test_load_add_and_validate_rows(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "config.json"
            path.write_text(json.dumps({
                "defaults": {"wind": {"alarm_bounds": {"level1": [0, 25]}}},
                "per_point": {"wind": {"W1": {"alarm_bounds": {"level2": [0, 30]}}}},
            }), encoding="utf-8")
            widget = AlarmBoundsEditorWidget()
            try:
                widget.load_path(path)
                self.assertEqual(widget.table.rowCount(), 2)
                widget.add_row("per_point")
                self.assertEqual(widget.table.rowCount(), 3)
                self.assertEqual(len(widget.rows()), 3)
            finally:
                widget.close()


if __name__ == "__main__":
    unittest.main()
