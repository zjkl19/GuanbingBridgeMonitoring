from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from .models import JobContext


@dataclass(frozen=True)
class AnalysisResultLocation:
    """Operator-facing location of one analysis run's durable outputs."""

    root: Path
    task_dir: Path | None = None
    manifest_path: Path | None = None

    @property
    def stats_dir(self) -> Path:
        return self.root / "stats"

    @property
    def run_logs_dir(self) -> Path:
        return self.root / "run_logs"

    @property
    def explanation(self) -> str:
        text = (
            f"统计表：{self.stats_dir}；运行记录/结果清单：{self.run_logs_dir}；"
            "正式图件按分析类型保存在结果根目录下的各图件目录。"
        )
        if self.task_dir is not None:
            text += f" 当前任务方案与日志目录：{self.task_dir}。"
        text += (
            "若当前任务使用隔离验证/候选数据目录，结果只会出现在该候选目录，"
            "原始数据目录不会新增结果。报告 DOCX/PDF 是另一套输出，请在“报告生成”页查看报告输出目录。"
        )
        return text


def analysis_result_location(
    *,
    data_root: str | Path = "",
    context: JobContext | None = None,
) -> AnalysisResultLocation | None:
    """Resolve the real result root without creating or mutating it."""

    raw_root = context.data_root if context is not None else data_root
    if not str(raw_root or "").strip():
        return None
    root = Path(raw_root).expanduser().resolve(strict=False)
    task_dir: Path | None = None
    manifest_path: Path | None = None
    if context is not None:
        task_dir = context.context_path.expanduser().resolve(strict=False).parent
        if str(context.analysis.manifest_path or "").strip():
            manifest_path = Path(context.analysis.manifest_path).expanduser().resolve(
                strict=False
            )
    return AnalysisResultLocation(root, task_dir, manifest_path)
