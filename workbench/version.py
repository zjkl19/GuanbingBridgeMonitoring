from __future__ import annotations

import sys
from pathlib import Path


APP_DISPLAY_NAME = "桥梁健康监测工作台"
EXECUTABLE_FILENAME = f"{APP_DISPLAY_NAME}.exe"
LEGACY_EXECUTABLE_FILENAME = "BridgeMonitoringWorkbench.exe"
SUPPORTED_EXECUTABLE_FILENAMES = (EXECUTABLE_FILENAME, LEGACY_EXECUTABLE_FILENAME)


def project_root() -> Path:
    if getattr(sys, "frozen", False):
        return Path(sys.executable).resolve().parent
    return Path(__file__).resolve().parents[1]


def app_version(root: Path | None = None) -> str:
    version_file = (root or project_root()) / "VERSION"
    try:
        value = version_file.read_text(encoding="utf-8-sig").strip()
    except OSError:
        return "v1.8.0-rc2"
    return value or "v1.8.0-rc2"
