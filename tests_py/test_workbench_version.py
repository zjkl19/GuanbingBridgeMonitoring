from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from workbench.version import (
    APP_DISPLAY_NAME,
    EXECUTABLE_FILENAME,
    LEGACY_CHINESE_EXECUTABLE_FILENAME,
    LEGACY_ENGLISH_EXECUTABLE_FILENAME,
    SUPPORTED_EXECUTABLE_FILENAMES,
    app_version,
    project_root,
)


class WorkbenchVersionTests(unittest.TestCase):
    def test_user_facing_name_and_legacy_executable_contract(self) -> None:
        self.assertEqual(APP_DISPLAY_NAME, "桥梁健康监测工作平台")
        self.assertEqual(EXECUTABLE_FILENAME, "桥梁健康监测工作平台.exe")
        self.assertEqual(
            SUPPORTED_EXECUTABLE_FILENAMES,
            (
                EXECUTABLE_FILENAME,
                LEGACY_CHINESE_EXECUTABLE_FILENAME,
                LEGACY_ENGLISH_EXECUTABLE_FILENAME,
            ),
        )
        self.assertEqual(LEGACY_CHINESE_EXECUTABLE_FILENAME, "桥梁健康监测工作台.exe")
        self.assertEqual(LEGACY_ENGLISH_EXECUTABLE_FILENAME, "BridgeMonitoringWorkbench.exe")

    def test_source_project_root_contains_workbench_package(self) -> None:
        self.assertTrue((project_root() / "workbench").is_dir())

    def test_frozen_project_root_is_executable_directory(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            executable = Path(folder) / EXECUTABLE_FILENAME
            with (
                patch.object(sys, "frozen", True, create=True),
                patch.object(sys, "executable", str(executable)),
            ):
                self.assertEqual(project_root(), executable.parent.resolve())

    def test_app_version_reads_release_file(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / "VERSION").write_text("v9.8.7\n", encoding="utf-8")
            self.assertEqual(app_version(root), "v9.8.7")


if __name__ == "__main__":
    unittest.main()
