from __future__ import annotations

import re


_STATE_LABELS = {
    "blocked": "等待完成前置检查",
    "draft": "任务草稿",
    "prepared": "任务已准备",
    "launched": "正在启动",
    "running": "正在处理",
    "stopping": "正在停止",
    "completed": "已完成",
    "success": "已完成",
    "passed": "通过",
    "ok": "通过",
    "failed": "失败",
    "stopped": "已停止",
    "launch_failed": "启动失败",
    "unknown": "状态未知",
    "missing": "未找到",
    "warning": "需要检查",
    "unavailable": "暂不可用",
    "invalid": "不可恢复",
}

_STAGE_LABELS = {
    "loading": "读取任务配置",
    "validating": "检查报告输入",
    "building": "生成报告",
    "rendering": "逐页渲染",
    "qc": "质量检查",
    "completed": "完成",
    "failed": "失败",
    "stop_requested": "正在安全停止",
    "status_retry": "重新读取状态",
    "process_start": "启动子进程",
    "process_exit": "子进程已退出",
}

_TERM_REPLACEMENTS = (
    (r"\bsource\s+provenance\b", "图件数据来源记录"),
    (r"\brelease\s+manifest\b", "更新包内容清单"),
    (r"\breport\s+manifest\b", "报告内容清单"),
    (r"\bmanifest\b", "结果清单"),
    (r"\bprovenance\b", "数据来源记录"),
    (r"\bstandalone\s+report\s+builder\b", "旧版独立报告组件"),
    (r"\breport\s+builder\b", "报告生成组件"),
    (r"\brelease\s+gate\b", "发布校验项"),
    (r"\bgate\b", "校验项"),
    (r"\blegacy\b", "历史兼容"),
    (r"\bqc\b", "质量检查"),
    (r"\bfile\s+inventory\b", "文件清单"),
    (r"\bschema_version\b", "格式版本"),
)


def operator_state_label(value: object) -> str:
    raw = str(value or "").strip()
    return _STATE_LABELS.get(raw.casefold(), operator_friendly_text(raw))


def operator_stage_label(value: object) -> str:
    raw = str(value or "").strip()
    return _STAGE_LABELS.get(raw.casefold(), operator_state_label(raw))


def operator_friendly_text(value: object) -> str:
    text = str(value or "")
    for pattern, replacement in _TERM_REPLACEMENTS:
        text = re.sub(pattern, replacement, text, flags=re.IGNORECASE)
    return text
