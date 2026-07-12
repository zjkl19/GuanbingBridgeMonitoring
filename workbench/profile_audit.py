from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from .models import file_sha256


class ProfileAuditError(RuntimeError):
    pass


@dataclass(frozen=True)
class InstalledProfileMatrix:
    path: Path
    executable_sha256: str
    profile_count: int
    report_capable_count: int
    analysis_only_count: int
    asset_count: int
    elapsed_seconds: float
    profiles: tuple[dict[str, Any], ...]


def load_installed_profile_matrix(project_root: Path) -> InstalledProfileMatrix:
    project_root = project_root.expanduser().resolve()
    path = project_root / "workbench_profile_matrix.json"
    if not path.is_file():
        raise ProfileAuditError("当前是源码/未完成打包的工作台，尚无冻结版六桥自检矩阵")
    try:
        payload = json.loads(path.read_text(encoding="utf-8-sig"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ProfileAuditError(f"六桥自检矩阵无法读取：{exc}") from exc
    if not isinstance(payload, dict) or int(payload.get("schema_version") or 0) != 1:
        raise ProfileAuditError("六桥自检矩阵格式或版本无效")
    rows = payload.get("profiles")
    if payload.get("status") != "passed" or not isinstance(rows, list):
        raise ProfileAuditError("六桥自检矩阵未通过")
    ids = [str(row.get("bridge_id") or "") for row in rows if isinstance(row, dict)]
    if len(rows) != 6 or len(ids) != 6 or len(set(ids)) != 6 or any(not item for item in ids):
        raise ProfileAuditError("六桥自检矩阵必须包含六个唯一项目")
    for row in rows:
        if not isinstance(row, dict):
            raise ProfileAuditError("六桥自检矩阵项目行无效")
        checks = row.get("checks")
        if not isinstance(checks, dict) or not checks or not all(value is True for value in checks.values()):
            raise ProfileAuditError(f"六桥自检项目未完全通过：{row.get('bridge_id', '')}")
    report_capable = int(payload.get("report_capable_count") or 0)
    analysis_only = int(payload.get("analysis_only_count") or 0)
    if report_capable != 5 or analysis_only != 1 or payload.get("assets_unchanged") is not True:
        raise ProfileAuditError("六桥报告能力或配置资产闭环不符合 5+1 约定")

    manifest_path = project_root / "release_manifest.json"
    if manifest_path.is_file():
        try:
            manifest = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
        except (OSError, json.JSONDecodeError) as exc:
            raise ProfileAuditError(f"发布清单无法读取：{exc}") from exc
        inventory = manifest.get("file_inventory") if isinstance(manifest, dict) else None
        matches = [
            row
            for row in inventory or []
            if isinstance(row, dict) and row.get("path") == "workbench_profile_matrix.json"
        ]
        if len(matches) != 1:
            raise ProfileAuditError("发布清单没有唯一固定六桥自检矩阵")
        record = matches[0]
        if int(record.get("bytes") or -1) != path.stat().st_size:
            raise ProfileAuditError("六桥自检矩阵大小与发布清单不一致")
        if str(record.get("sha256") or "").lower() != file_sha256(path).lower():
            raise ProfileAuditError("六桥自检矩阵 SHA256 与发布清单不一致")

    return InstalledProfileMatrix(
        path=path,
        executable_sha256=str(payload.get("executable_sha256") or ""),
        profile_count=len(rows),
        report_capable_count=report_capable,
        analysis_only_count=analysis_only,
        asset_count=int(payload.get("asset_count") or 0),
        elapsed_seconds=float(payload.get("elapsed_seconds") or 0),
        profiles=tuple(rows),
    )
