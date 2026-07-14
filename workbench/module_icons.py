from __future__ import annotations

from pathlib import Path

from PySide6 import QtSvg  # noqa: F401 - ensures SVG support is packaged
from PySide6.QtGui import QIcon


def module_icon(project_root: Path, asset_name: str) -> QIcon:
    path = project_root / "workbench" / "assets" / "module_icons" / asset_name
    return QIcon(str(path)) if path.is_file() else QIcon()
