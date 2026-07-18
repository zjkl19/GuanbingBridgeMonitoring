from __future__ import annotations

import sys
from pathlib import Path


APP_DISPLAY_NAME = "桥梁健康监测工作平台"
EXECUTABLE_FILENAME = f"{APP_DISPLAY_NAME}.exe"
LEGACY_CHINESE_EXECUTABLE_FILENAME = "桥梁健康监测工作台.exe"
LEGACY_ENGLISH_EXECUTABLE_FILENAME = "BridgeMonitoringWorkbench.exe"
# Keep the original public constant as an alias for callers that predate the
# Chinese executable name.  Internal package paths and settings identities stay
# unchanged; only the user-facing executable is renamed.
LEGACY_EXECUTABLE_FILENAME = LEGACY_ENGLISH_EXECUTABLE_FILENAME
SUPPORTED_EXECUTABLE_FILENAMES = (
    EXECUTABLE_FILENAME,
    LEGACY_CHINESE_EXECUTABLE_FILENAME,
    LEGACY_ENGLISH_EXECUTABLE_FILENAME,
)
DEFAULT_VERSION = "v1.8.2-dev"


def project_root() -> Path:
    if getattr(sys, "frozen", False):
        return Path(sys.executable).resolve().parent
    return Path(__file__).resolve().parents[1]


def app_version(root: Path | None = None) -> str:
    version_file = (root or project_root()) / "VERSION"
    try:
        value = version_file.read_text(encoding="utf-8-sig").strip()
    except OSError:
        return DEFAULT_VERSION
    return value or DEFAULT_VERSION
