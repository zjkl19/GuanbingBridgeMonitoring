from __future__ import annotations

import ctypes
import os
from pathlib import Path

from PySide6.QtGui import QIcon


APP_USER_MODEL_ID = "Guanbing.BridgeMonitoringWorkbench"


def application_icon(project_root: Path) -> QIcon:
    asset_root = project_root / "workbench" / "assets"
    for name in ("app_icon.ico", "app_icon.png", "app_icon.svg"):
        path = asset_root / name
        if path.is_file():
            icon = QIcon(str(path))
            if not icon.isNull():
                return icon
    return QIcon()


def organization_logo_path(project_root: Path) -> Path | None:
    """Return an explicitly supplied organization logo; never invent one."""

    asset_root = project_root / "workbench" / "assets"
    for name in ("organization_logo.svg", "organization_logo.png"):
        path = asset_root / name
        if path.is_file():
            return path
    return None


def set_windows_app_user_model_id(app_id: str = APP_USER_MODEL_ID) -> bool:
    if os.name != "nt":
        return False
    try:
        ctypes.windll.shell32.SetCurrentProcessExplicitAppUserModelID(app_id)
    except (AttributeError, OSError):
        return False
    return True
