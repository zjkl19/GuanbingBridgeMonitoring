from __future__ import annotations

import json
import os
import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any


@dataclass(frozen=True)
class WorkbenchProfile:
    bridge_id: str
    bridge_name: str
    default_config: str = ""
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
    optional_modules: tuple[str, ...] = field(default_factory=tuple)

    @classmethod
    def from_mapping(cls, raw: dict[str, Any]) -> "WorkbenchProfile":
        values = {field_name: str(raw.get(field_name, "")) for field_name in (
            "bridge_id", "bridge_name", "default_config",
            "default_data_root", "data_layout", "report_type", "report_gui_type",
            "report_template", "wim_default_dir", "default_period_label",
            "default_monitoring_range", "default_report_date", "default_start_date",
            "default_end_date",
        )}
        values["enabled_modules"] = tuple(str(item) for item in raw.get("enabled_modules", []))
        values["optional_modules"] = tuple(str(item) for item in raw.get("optional_modules", []))
        return cls(**values)

    def _resolve_project_path(self, value: str, project_root: Path) -> Path:
        expanded = value.replace("<COMPUTERNAME>", os.environ.get("COMPUTERNAME", ""))
        path = Path(expanded)
        return path if path.is_absolute() else project_root / path

    def config_path(self, project_root: Path) -> Path:
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


@dataclass(frozen=True)
class MachinePathProfile:
    """One machine/storage layout without duplicating bridge business settings."""

    profile_id: str
    display_name: str
    hostnames: tuple[str, ...] = field(default_factory=tuple)
    data_roots: dict[str, str] = field(default_factory=dict)
    path_replacements: tuple[tuple[str, str], ...] = field(default_factory=tuple)
    source_path: str = ""
    match_type: str = "manual"
    match_reason: str = ""

    @classmethod
    def from_mapping(cls, raw: dict[str, Any], source: Path) -> "MachinePathProfile":
        replacements: list[tuple[str, str]] = []
        for item in raw.get("path_replacements", []) or []:
            if isinstance(item, dict) and str(item.get("from") or "").strip():
                replacements.append((str(item["from"]), str(item.get("to") or "")))
        roots = raw.get("data_roots") or {}
        return cls(
            profile_id=str(raw.get("profile_id") or "").strip(),
            display_name=str(raw.get("display_name") or raw.get("profile_id") or "").strip(),
            hostnames=tuple(str(item).strip() for item in raw.get("hostnames", []) if str(item).strip()),
            data_roots={str(key).lower(): str(value) for key, value in roots.items()}
            if isinstance(roots, dict)
            else {},
            path_replacements=tuple(replacements),
            source_path=str(source.resolve()),
        )

    def marked(self, match_type: str, reason: str) -> "MachinePathProfile":
        return MachinePathProfile(
            self.profile_id,
            self.display_name,
            self.hostnames,
            self.data_roots,
            self.path_replacements,
            self.source_path,
            match_type,
            reason,
        )


class PathProfileResolver:
    """Resolve the active machine path group using the MATLAB resolver priority.

    Priority is: ``GUANBING_PATH_PROFILE`` -> ``COMPUTERNAME`` -> an existing
    configured path -> bridge catalog default.  ``path_profiles.local.json`` is
    loaded after the shared file so a local entry can intentionally override a
    shared entry with the same id or hostname.
    """

    AUTO_ID = "__auto__"
    CUSTOM_ID = "__custom__"
    _TOKEN = re.compile(r"<(?P<name>project_root|COMPUTERNAME)>", re.IGNORECASE)

    def __init__(self, project_root: Path, environ: dict[str, str] | None = None) -> None:
        self.project_root = project_root.expanduser().resolve()
        self.environ = dict(os.environ if environ is None else environ)
        self.profiles = self._load_profiles()

    def _load_profiles(self) -> list[MachinePathProfile]:
        rows: list[MachinePathProfile] = []
        for source in (
            self.project_root / "config" / "path_profiles.json",
            self.project_root / "config" / "path_profiles.local.json",
        ):
            if not source.is_file():
                continue
            payload = json.loads(source.read_text(encoding="utf-8-sig"))
            for raw in payload.get("profiles", []) if isinstance(payload, dict) else []:
                if not isinstance(raw, dict):
                    continue
                profile = MachinePathProfile.from_mapping(raw, source)
                if profile.profile_id:
                    rows.append(profile)
        return rows

    def by_id(self, profile_id: str) -> MachinePathProfile | None:
        wanted = profile_id.strip().casefold()
        return next(
            (item for item in reversed(self.profiles) if item.profile_id.casefold() == wanted),
            None,
        )

    def active(self) -> MachinePathProfile | None:
        requested = self.environ.get("GUANBING_PATH_PROFILE", "").strip()
        if requested:
            profile = self.by_id(requested)
            if profile is not None:
                return profile.marked("env", f"环境变量指定：GUANBING_PATH_PROFILE={requested}")
            return None

        host = self.environ.get("COMPUTERNAME", "").strip()
        if host:
            wanted = host.casefold()
            for profile in reversed(self.profiles):
                if any(item.casefold() in {wanted, "*"} for item in profile.hostnames):
                    return profile.marked("host", f"按电脑名自动匹配：{host}")

        scored = [(self._profile_path_score(item), index, item) for index, item in enumerate(self.profiles)]
        if scored:
            # Later entries win a score tie. The optional local file is loaded
            # after the shared file, matching the MATLAB resolver's reverse
            # traversal and making a same-id local override deterministic.
            score, _index, profile = max(scored, key=lambda row: (row[0], row[1]))
            if score > 0:
                return profile.marked("path_exists", "按本机已有数据目录自动匹配")
        return None

    def select(self, profile_id: str) -> MachinePathProfile | None:
        if not profile_id or profile_id == self.AUTO_ID:
            return self.active()
        if profile_id == self.CUSTOM_ID:
            return None
        profile = self.by_id(profile_id)
        return profile.marked("manual", "用户在工作平台中手动选择") if profile else None

    def resolve_data_root(
        self,
        bridge_id: str,
        default_root: str,
        profile: MachinePathProfile | None = None,
    ) -> str:
        selected = profile if profile is not None else self.active()
        root = self._resolve_tokens(default_root)
        if selected is None:
            return root
        explicit = selected.data_roots.get(bridge_id.strip().lower(), "").strip()
        if explicit:
            return self._resolve_tokens(explicit)
        for source, target in selected.path_replacements:
            source_text = self._resolve_tokens(source)
            if self._is_path_prefix(root, source_text):
                return self._normalize(self._resolve_tokens(target) + root[len(source_text):])
        return root

    def describe(self, profile: MachinePathProfile | None) -> str:
        if profile is None:
            return "未匹配机器配置组，使用桥梁默认路径；也可选择“自定义路径”后浏览目录。"
        return f"当前配置组：{profile.display_name}（{profile.match_reason}）"

    def _profile_path_score(self, profile: MachinePathProfile) -> int:
        score = 0
        for raw in profile.data_roots.values():
            score += self._path_score(raw, exact=4)
        for _source, target in profile.path_replacements:
            score += self._path_score(target, exact=3)
        return score

    def _path_score(self, raw: str, *, exact: int) -> int:
        text = self._resolve_tokens(raw)
        if not text:
            return 0
        path = Path(text)
        if path.is_dir():
            return exact
        parent = path.parent
        if parent == path or str(parent) == str(Path(parent.anchor)):
            return 0
        return 1 if parent.is_dir() else 0

    def _resolve_tokens(self, value: str) -> str:
        replacements = {
            "project_root": str(self.project_root),
            "computername": self.environ.get("COMPUTERNAME", ""),
        }
        return self._normalize(
            self._TOKEN.sub(lambda match: replacements[match.group("name").casefold()], str(value or ""))
        )

    @staticmethod
    def _normalize(value: str) -> str:
        text = str(value or "").strip().replace("/", os.sep).replace("\\", os.sep)
        return os.path.normpath(text) if text else ""

    @staticmethod
    def _is_path_prefix(path: str, prefix: str) -> bool:
        path_text = os.path.normcase(os.path.normpath(path))
        prefix_text = os.path.normcase(os.path.normpath(prefix))
        if path_text == prefix_text:
            return True
        return path_text.startswith(prefix_text.rstrip("\\/") + os.sep)
