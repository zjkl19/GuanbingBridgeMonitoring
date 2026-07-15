from __future__ import annotations

import copy
import math
from dataclasses import dataclass
from typing import Any


DEFAULT_WORKERS = 1
AUTO_TOKEN = "auto"
AUTO_MAX_WORKERS = 2
MAX_CUSTOM_WORKERS = 64
PRESET_WORKERS = (1, 2, 4)


class UnzipWorkerConfigError(ValueError):
    pass


@dataclass(frozen=True)
class UnzipWorkerSetting:
    mode: str
    requested_workers: int | str
    worker_limit: int

    @property
    def is_auto(self) -> bool:
        return self.mode == "auto"

    @property
    def is_preset(self) -> bool:
        return isinstance(self.requested_workers, int) and self.requested_workers in PRESET_WORKERS


def normalize_unzip_worker_setting(value: Any = None) -> UnzipWorkerSetting:
    """Normalize the JSON contract without silently coercing bad values.

    A missing/null value preserves the historical serial default.  Existing
    positive JSON numbers remain valid, while the new ``"auto"`` token uses a
    conservative two-worker cap.  Booleans are rejected even though Python's
    ``bool`` is an ``int`` subclass.
    """

    if value is None:
        value = DEFAULT_WORKERS
    if isinstance(value, str):
        if value.strip().lower() == AUTO_TOKEN:
            return UnzipWorkerSetting("auto", AUTO_TOKEN, AUTO_MAX_WORKERS)
        raise UnzipWorkerConfigError(
            f'preprocessing.unzip.max_workers 必须是 "{AUTO_TOKEN}"，'
            f"或 1 至 {MAX_CUSTOM_WORKERS} 之间的正整数"
        )
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise UnzipWorkerConfigError(
            f'preprocessing.unzip.max_workers 必须是 "{AUTO_TOKEN}"，'
            f"或 1 至 {MAX_CUSTOM_WORKERS} 之间的正整数"
        )
    number = float(value)
    if (
        not math.isfinite(number)
        or not number.is_integer()
        or number < 1
        or number > MAX_CUSTOM_WORKERS
    ):
        raise UnzipWorkerConfigError(
            f'preprocessing.unzip.max_workers 必须是 "{AUTO_TOKEN}"，'
            f"或 1 至 {MAX_CUSTOM_WORKERS} 之间的正整数"
        )
    workers = int(number)
    return UnzipWorkerSetting("fixed", workers, workers)


def unzip_worker_setting_from_config(payload: dict[str, Any]) -> UnzipWorkerSetting:
    if not isinstance(payload, dict):
        raise UnzipWorkerConfigError("配置文件根节点必须是 JSON 对象")
    preprocessing = payload.get("preprocessing")
    if preprocessing is None:
        return normalize_unzip_worker_setting()
    if not isinstance(preprocessing, dict):
        raise UnzipWorkerConfigError("preprocessing 必须是 JSON 对象")
    unzip = preprocessing.get("unzip")
    if unzip is None:
        return normalize_unzip_worker_setting()
    if not isinstance(unzip, dict):
        raise UnzipWorkerConfigError("preprocessing.unzip 必须是 JSON 对象")
    return normalize_unzip_worker_setting(unzip.get("max_workers"))


def apply_unzip_worker_setting(
    payload: dict[str, Any], value: Any
) -> dict[str, Any]:
    setting = normalize_unzip_worker_setting(value)
    if not isinstance(payload, dict):
        raise UnzipWorkerConfigError("配置文件根节点必须是 JSON 对象")
    updated = copy.deepcopy(payload)
    preprocessing = updated.get("preprocessing")
    if preprocessing is None:
        preprocessing = {}
        updated["preprocessing"] = preprocessing
    if not isinstance(preprocessing, dict):
        raise UnzipWorkerConfigError("preprocessing 必须是 JSON 对象")
    unzip = preprocessing.get("unzip")
    if unzip is None:
        unzip = {}
        preprocessing["unzip"] = unzip
    if not isinstance(unzip, dict):
        raise UnzipWorkerConfigError("preprocessing.unzip 必须是 JSON 对象")
    unzip["max_workers"] = setting.requested_workers
    return updated


def unzip_worker_summary(setting: UnzipWorkerSetting) -> str:
    if setting.is_auto:
        return "自动：按 ZIP 数量决定，最多使用 2 个 MATLAB 工作进程；不可用时回退串行。"
    if setting.worker_limit == 1:
        return "串行：一次处理 1 个 ZIP；这是缺失配置时的兼容安全默认值。"
    return (
        f"并行：最多同时处理 {setting.worker_limit} 个 ZIP；"
        "实际工作进程数受 ZIP 数量、本机并行环境和输出目录安全约束限制。"
    )
