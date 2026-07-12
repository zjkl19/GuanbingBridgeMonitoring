from __future__ import annotations

from pathlib import Path


def project_root() -> Path:
    return Path(__file__).resolve().parents[1]


def app_version(root: Path | None = None) -> str:
    version_file = (root or project_root()) / "VERSION"
    try:
        value = version_file.read_text(encoding="utf-8-sig").strip()
    except OSError:
        return "v1.7.39-dev"
    return value or "v1.7.39-dev"
