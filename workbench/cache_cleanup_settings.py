from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from typing import Any, Iterable


CACHE_SOURCE_CLEANUP_KEY = "cache_source_cleanup"
CACHE_SOURCE_CLEANUP_CONFIRMATION = "DELETE_VERIFIED_EXTRACTED_CSV"
CACHE_SOURCE_CLEANUP_MODE = "verified_extracted_csv"
CACHE_SOURCE_CLEANUP_SCOPE = "day"
CACHE_SOURCE_CLEANUP_RECOVERY = "verified_archive"
CACHE_SOURCE_CLEANUP_SUPPORTED_LAYOUTS = frozenset(
    {"jlj_daily_export", "dated_folders", "hongtang_period"}
)
CACHE_SOURCE_CLEANUP_CONFLICTS = frozenset({"rename_csv", "remove_header", "resample"})
CACHE_SOURCE_CLEANUP_ALLOWED_MODULES = frozenset(
    {"zip_precheck", "unzip", "cache_prebuild"}
)


@dataclass(frozen=True)
class CacheSourceCleanupSettings:
    """Task-scoped opt-in for deleting archive-recoverable extracted CSV files."""

    enabled: bool = False
    confirmation: str = ""
    confirmed_at: str = ""
    policy_compatible: bool = True

    def validated(
        self, selected_modules: Iterable[str], *, data_layout: str = ""
    ) -> "CacheSourceCleanupSettings":
        modules = {str(item).strip() for item in selected_modules}
        if not self.enabled:
            return CacheSourceCleanupSettings()
        if "cache_prebuild" not in modules:
            raise ValueError("只有选择“预生成分析缓存”后，才能删除已解压 CSV")
        conflicts = sorted(modules.intersection(CACHE_SOURCE_CLEANUP_CONFLICTS))
        if conflicts:
            labels = {
                "rename_csv": "批量重命名CSV",
                "remove_header": "批量去除表头",
                "resample": "批量重采样",
            }
            raise ValueError(
                "删除已解压 CSV 不能与以下会修改 CSV 的步骤同时运行："
                + "、".join(labels[item] for item in conflicts)
            )
        later_modules = sorted(modules.difference(CACHE_SOURCE_CLEANUP_ALLOWED_MODULES))
        if later_modules:
            raise ValueError(
                "为防止清理失败后继续使用不完整月份，本功能必须作为独立预处理任务运行；"
                "请先只运行压缩包预检查/批量解压/预生成分析缓存，完成后再新建分析任务"
            )
        if data_layout and data_layout not in CACHE_SOURCE_CLEANUP_SUPPORTED_LAYOUTS:
            raise ValueError(
                "当前数据目录格式不支持安全删除；系统只处理具备原 ZIP、有效解压清单、"
                "唯一 ZIP 条目证明和独立可读 MAT 缓存的逐日数据"
            )
        if self.confirmation != CACHE_SOURCE_CLEANUP_CONFIRMATION:
            raise ValueError(
                f"请输入完整确认口令：{CACHE_SOURCE_CLEANUP_CONFIRMATION}"
            )
        return CacheSourceCleanupSettings(
            enabled=True,
            confirmation=CACHE_SOURCE_CLEANUP_CONFIRMATION,
            confirmed_at=self.confirmed_at.strip(),
        )

    def to_task_option(self, selected_modules: Iterable[str]) -> dict[str, Any]:
        checked = self.validated(selected_modules)
        if not checked.enabled:
            return {}
        confirmed_at = checked.confirmed_at or datetime.now().astimezone().isoformat(
            timespec="seconds"
        )
        return {
            "enabled": True,
            "mode": CACHE_SOURCE_CLEANUP_MODE,
            "commit_scope": CACHE_SOURCE_CLEANUP_SCOPE,
            "recovery_policy": CACHE_SOURCE_CLEANUP_RECOVERY,
            "confirmation": CACHE_SOURCE_CLEANUP_CONFIRMATION,
            "confirmed_at": confirmed_at,
        }

    @classmethod
    def from_task_options(cls, options: dict[str, Any] | None) -> "CacheSourceCleanupSettings":
        if not isinstance(options, dict):
            return cls()
        raw = options.get(CACHE_SOURCE_CLEANUP_KEY)
        if not isinstance(raw, dict) or raw.get("enabled") is not True:
            return cls()
        # Unknown or incomplete policies are shown as enabled but deliberately
        # lose confirmation.  Validation will then fail closed before save/run.
        compatible = (
            str(raw.get("mode", "")) == CACHE_SOURCE_CLEANUP_MODE
            and str(raw.get("commit_scope", "")) == CACHE_SOURCE_CLEANUP_SCOPE
            and str(raw.get("recovery_policy", "")) == CACHE_SOURCE_CLEANUP_RECOVERY
        )
        confirmation = str(raw.get("confirmation", "")) if compatible else ""
        return cls(
            enabled=True,
            confirmation=confirmation,
            confirmed_at=str(raw.get("confirmed_at", "")),
            policy_compatible=compatible,
        )


def cleanup_validation_errors(
    selected_modules: Iterable[str], *, enabled: bool, confirmation: str,
    data_layout: str = "",
) -> list[str]:
    try:
        CacheSourceCleanupSettings(enabled, confirmation).validated(
            selected_modules, data_layout=data_layout
        )
    except ValueError as exc:
        return [str(exc)]
    return []
