from __future__ import annotations

import re


_STATE_LABELS = {
    "blocked": "等待完成前置检查",
    "draft": "任务草稿",
    "prepared": "任务已准备",
    "ready": "可生成报告",
    "launched": "正在启动",
    "running": "正在处理",
    "stopping": "正在停止",
    "completed": "已完成",
    "disclosure_required": "等待逐项确认黄色缺项",
    "success": "已完成",
    "passed": "通过",
    "passed_with_disclosures": "通过（含缺项披露）",
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
    "disclosure_review": "逐项确认黄色缺项",
    "validate_request": "检查任务参数",
    "loading_config": "读取配置",
    "load_curve": "读取当前测点曲线",
    "load_date": "读取日期数据",
    "load_cache_date": "读取 MAT 缓存日期",
    "load_source_date": "读取源数据日期",
    "curve_ready": "当前测点曲线已就绪",
    "generate_proposals": "运行自动阈值算法",
    "point_complete": "当前测点建议已完成",
    "build_preview": "生成曲线预览",
    "write_preview": "写入曲线预览",
    "write_record": "写入曲线记录",
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
    point_not_configured = re.fullmatch(
        r"Point\s+(.+?)\s+is\s+not\s+configured\s+for\s+module\s+(.+?)\.?",
        text.strip(),
        flags=re.IGNORECASE,
    )
    if point_not_configured:
        point_id, module_key = point_not_configured.groups()
        return (
            f"测点 {point_id} 未能唯一映射到分析模块 {module_key} 的配置测点。"
            "请核对清洗规则中的测点编号与项目测点清单；若只是连字符和下划线差异，"
            "新版工作平台会自动按唯一别名映射。"
        )
    for pattern, replacement in _TERM_REPLACEMENTS:
        text = re.sub(pattern, replacement, text, flags=re.IGNORECASE)
    return text
