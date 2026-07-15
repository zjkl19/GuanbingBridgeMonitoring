from __future__ import annotations

import argparse
import os
import sys
import traceback
from datetime import datetime
from pathlib import Path
from typing import Any

from report_job import ReportJobRequest, execute_report_job

PROJECT_ROOT = Path(__file__).resolve().parents[1]
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

from workbench.models import JobContext
from workbench.process_utils import atomic_write_json
from workbench.report_gate import require_report_gate


def _write_json(path: Path, payload: dict[str, Any]) -> None:
    atomic_write_json(path, payload)


def request_from_job_context(context: JobContext) -> ReportJobRequest:
    require_report_gate(context)
    result_root = Path(context.data_root).expanduser().resolve()
    report_type = context.report.report_type.strip()
    return ReportJobRequest(
        report_type=report_type,
        template=Path(context.report.template_path).expanduser().resolve(),
        config_path=Path(context.config_path).expanduser().resolve(),
        result_root=result_root,
        analysis_root=Path(context.project_root or Path.cwd()).expanduser().resolve(),
        output_dir=Path(context.report.output_dir or result_root / "自动报告").expanduser().resolve(),
        period_label=context.period_label,
        monitoring_range=context.monitoring_range,
        report_date=context.report_date,
        start_date=context.start_date,
        end_date=context.end_date,
        wim_root=(
            result_root / "WIM" / "results" / "hongtang"
            if report_type == "hongtang_period_wim"
            else None
        ),
        analysis_manifest_path=Path(context.analysis.manifest_path).expanduser().resolve(),
        analysis_manifest_sha256=context.analysis.manifest_sha256,
        derived_artifact_manifest_path=(
            Path(context.report.derived_artifact_manifest_path).expanduser().resolve()
            if context.report.derived_artifact_manifest_path
            else None
        ),
        derived_artifact_manifest_sha256=context.report.derived_artifact_manifest_sha256,
        require_source_provenance=True,
    )


def request_from_context(source: Path | JobContext) -> ReportJobRequest:
    context = source if isinstance(source, JobContext) else JobContext.read(source)
    return request_from_job_context(context)


def run_context(
    context_path: Path,
    status_path: Path,
    result_path: Path,
    expected_launch_id: str = "",
) -> int:
    started = datetime.now().astimezone().isoformat(timespec="seconds")
    launch_id = str(expected_launch_id or "")

    def progress(stage: str, fraction: float, message: str) -> None:
        _write_json(status_path, {
            "schema_version": 1,
            # The result file is the commit record for a successful report.
            # Progress callbacks may announce a "completed" stage before the
            # result payload is durable, so they must never publish a terminal
            # state on their own.
            "state": "running",
            "launch_id": launch_id,
            "stage": stage,
            "progress_fraction": fraction,
            "message": message,
            "started_at": started,
            "updated_at": datetime.now().astimezone().isoformat(timespec="seconds"),
            "pid": os.getpid(),
            "result_path": str(result_path),
        })

    try:
        # Read exactly once. The workbench passes a per-launch immutable
        # snapshot, and direct callers still get one internally consistent
        # request if another process replaces the source file afterwards.
        context = JobContext.read(context_path)
        context_launch_id = str(context.report.launch_id or "")
        if launch_id and context_launch_id != launch_id:
            raise RuntimeError(
                "报告任务上下文已被另一轮启动覆盖，拒绝使用不匹配的启动标识。"
            )
        if not launch_id:
            launch_id = context_launch_id
        progress("loading", 0.01, "正在读取并校验工作台任务上下文")
        request = request_from_context(context)
        result = execute_report_job(request, progress)
        payload = {
            "schema_version": 1,
            "state": "completed",
            "launch_id": launch_id,
            "report_path": str(result.report_path),
            "pdf_path": str(result.pdf_path or ""),
            "manifest_path": str(result.manifest_path or ""),
            "missing": list(result.missing),
            "summary_files": [str(path) for path in result.summary_files],
            "qc": result.qc,
        }
        _write_json(result_path, payload)
        _write_json(status_path, {
            "schema_version": 1,
            "state": "completed",
            "launch_id": launch_id,
            "stage": "completed",
            "progress_fraction": 1.0,
            "message": "报告生成与 QC 已完成",
            "started_at": started,
            "updated_at": datetime.now().astimezone().isoformat(timespec="seconds"),
            "pid": os.getpid(),
            "result_path": str(result_path),
        })
        return 0
    except Exception as exc:  # noqa: BLE001
        _write_json(result_path, {
            "schema_version": 1,
            "state": "failed",
            "launch_id": launch_id,
            "error": str(exc),
            "traceback": traceback.format_exc(),
        })
        _write_json(status_path, {
            "schema_version": 1,
            "state": "failed",
            "launch_id": launch_id,
            "stage": "failed",
            "progress_fraction": 1.0,
            "message": str(exc),
            "started_at": started,
            "updated_at": datetime.now().astimezone().isoformat(timespec="seconds"),
            "pid": os.getpid(),
            "result_path": str(result_path),
        })
        return 1


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Run one approved workbench report job.")
    parser.add_argument("--job-context", type=Path, required=True)
    parser.add_argument("--status", type=Path, required=True)
    parser.add_argument("--result", type=Path, required=True)
    parser.add_argument("--launch-id", default="")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    return run_context(
        args.job_context.resolve(),
        args.status.resolve(),
        args.result.resolve(),
        args.launch_id,
    )


if __name__ == "__main__":
    raise SystemExit(main())
