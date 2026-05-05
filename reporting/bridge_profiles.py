from __future__ import annotations

import json
import os
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any


@dataclass(frozen=True)
class BridgeProfile:
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
    default_start_date: str = ""
    default_end_date: str = ""
    enabled_modules: list[str] = field(default_factory=list)

    @classmethod
    def from_mapping(cls, raw: dict[str, Any]) -> "BridgeProfile":
        return cls(
            bridge_id=str(raw.get("bridge_id", "")),
            bridge_name=str(raw.get("bridge_name", raw.get("bridge_id", ""))),
            default_config=str(raw.get("default_config", "")),
            machine_config_pattern=str(raw.get("machine_config_pattern", "")),
            default_data_root=str(raw.get("default_data_root", "")),
            data_layout=str(raw.get("data_layout", "")),
            report_type=str(raw.get("report_type", "")),
            report_gui_type=str(raw.get("report_gui_type", "")),
            report_template=str(raw.get("report_template", "")),
            wim_default_dir=str(raw.get("wim_default_dir", "")),
            default_period_label=str(raw.get("default_period_label", "")),
            default_monitoring_range=str(raw.get("default_monitoring_range", "")),
            default_start_date=str(raw.get("default_start_date", "")),
            default_end_date=str(raw.get("default_end_date", "")),
            enabled_modules=[str(item) for item in raw.get("enabled_modules", [])],
        )

    def resolve_path(self, value: str, root: Path) -> Path:
        text = value.replace("<COMPUTERNAME>", os.environ.get("COMPUTERNAME", ""))
        path = Path(text)
        if not path.is_absolute():
            path = root / path
        return path.resolve()

    def config_path(self, root: Path) -> Path:
        if self.machine_config_pattern:
            machine_path = self.resolve_path(self.machine_config_pattern, root)
            if machine_path.exists():
                return machine_path
        return self.resolve_path(self.default_config, root)

    def template_path(self, root: Path) -> Path:
        return self.resolve_path(self.report_template, root)

    def data_root_path(self) -> Path:
        return Path(self.default_data_root)

    def wim_root_for(self, data_root: Path) -> Path:
        if self.wim_default_dir:
            return Path(self.wim_default_dir.replace("<data_root>", str(data_root)))
        return data_root / "WIM" / "results" / "hongtang"


def load_profiles(project_root: Path) -> list[BridgeProfile]:
    profile_path = project_root / "config" / "bridge_profiles.json"
    if profile_path.exists():
        data = json.loads(profile_path.read_text(encoding="utf-8"))
        return [BridgeProfile.from_mapping(item) for item in data.get("profiles", [])]
    return fallback_profiles()


def fallback_profiles() -> list[BridgeProfile]:
    return [
        BridgeProfile(
            bridge_id="guanbing",
            bridge_name="管柄大桥",
            default_config="config/default_config.json",
            default_data_root=r"F:\管柄大桥数据\2026年4月",
            data_layout="dated_folders",
            report_gui_type="guanbing_monthly",
            report_template="reports/G104线管柄大桥监测月报模板-自动报告.docx",
        ),
        BridgeProfile(
            bridge_id="hongtang",
            bridge_name="洪塘大桥",
            default_config="config/hongtang_config.json",
            machine_config_pattern="config/hongtang_config_<COMPUTERNAME>.json",
            default_data_root=r"E:\洪塘大桥数据\2026年1-3月",
            data_layout="hongtang_period",
            report_gui_type="hongtang_period_wim",
            report_template="reports/洪塘大桥健康监测2026年第一季季报-改4.docx",
            wim_default_dir=r"<data_root>\WIM\results\hongtang",
        ),
        BridgeProfile(
            bridge_id="jiulongjiang",
            bridge_name="九龙江大桥",
            default_config="config/jiulongjiang_config.json",
            default_data_root=r"E:\九龙江数据\2026年3月",
            data_layout="jlj_daily_export",
            report_gui_type="jlj_monthly",
            report_template="reports/九龙江大桥健康监测2026年3月份月报_修订5.docx",
        ),
    ]


def profile_by_id(profiles: list[BridgeProfile], bridge_id: str) -> BridgeProfile:
    for profile in profiles:
        if profile.bridge_id == bridge_id:
            return profile
    if profiles:
        return profiles[0]
    raise ValueError("No bridge profiles available")
