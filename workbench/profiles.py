from __future__ import annotations

import json
import os
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any


@dataclass(frozen=True)
class WorkbenchProfile:
    bridge_id: str
    bridge_name: str
    default_config: str = ""
    machine_config_pattern: str = ""
    default_data_root: str = ""
    data_layout: str = ""
    report_type: str = ""
    report_gui_type: str = ""
    report_template: str = ""
    wim_default_dir: str = ""
    default_period_label: str = ""
    default_monitoring_range: str = ""
    default_report_date: str = ""
    default_start_date: str = ""
    default_end_date: str = ""
    enabled_modules: tuple[str, ...] = field(default_factory=tuple)

    @classmethod
    def from_mapping(cls, raw: dict[str, Any]) -> "WorkbenchProfile":
        values = {field_name: str(raw.get(field_name, "")) for field_name in (
            "bridge_id", "bridge_name", "default_config", "machine_config_pattern",
            "default_data_root", "data_layout", "report_type", "report_gui_type",
            "report_template", "wim_default_dir", "default_period_label",
            "default_monitoring_range", "default_report_date", "default_start_date",
            "default_end_date",
        )}
        values["enabled_modules"] = tuple(str(item) for item in raw.get("enabled_modules", []))
        return cls(**values)

    def _resolve_project_path(self, value: str, project_root: Path) -> Path:
        expanded = value.replace("<COMPUTERNAME>", os.environ.get("COMPUTERNAME", ""))
        path = Path(expanded)
        return path if path.is_absolute() else project_root / path

    def config_path(self, project_root: Path) -> Path:
        if self.machine_config_pattern:
            machine_path = self._resolve_project_path(self.machine_config_pattern, project_root)
            if machine_path.exists():
                return machine_path.resolve()
        return self._resolve_project_path(self.default_config, project_root).resolve()

    def template_path(self, project_root: Path) -> Path:
        return self._resolve_project_path(self.report_template, project_root).resolve()


def load_profiles(project_root: Path) -> list[WorkbenchProfile]:
    source = project_root / "config" / "bridge_profiles.json"
    payload = json.loads(source.read_text(encoding="utf-8-sig"))
    profiles = [WorkbenchProfile.from_mapping(item) for item in payload.get("profiles", [])]
    if not profiles:
        raise ValueError(f"No bridge profiles found in {source}")
    return profiles


def profile_by_id(profiles: list[WorkbenchProfile], bridge_id: str) -> WorkbenchProfile:
    for profile in profiles:
        if profile.bridge_id == bridge_id:
            return profile
    raise KeyError(f"Unknown bridge profile: {bridge_id}")
