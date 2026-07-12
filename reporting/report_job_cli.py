from __future__ import annotations

import argparse
import json
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
from workbench.report_gate import require_report_gate


def _write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + f".{os.getpid()}.tmp")
    temporary.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    temporary.replace(path)


def request_from_context(path: Path) -> ReportJobRequest:
    context = JobContext.read(path)
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
    )


def run_context(context_path: Path, status_path: Path, result_path: Path) -> int:
    started = datetime.now().astimezone().isoformat(timespec="seconds")

    def progress(stage: str, fraction: float, message: str) -> None:
        _write_json(status_path, {
            "schema_version": 1,
            "state": "completed" if stage == "completed" else "running",
            "stage": stage,
            "progress_fraction": fraction,
            "message": message,
            "started_at": started,
            "updated_at": datetime.now().astimezone().isoformat(timespec="seconds"),
            "pid": os.getpid(),
            "result_path": str(result_path),
        })

    try:
        progress("loading", 0.01, "正在读取并校验工作台任务上下文")
        request = request_from_context(context_path)
        result = execute_report_job(request, progress)
        payload = {
            "schema_version": 1,
            "state": "completed",
            "report_path": str(result.report_path),
            "pdf_path": str(result.pdf_path or ""),
            "manifest_path": str(result.manifest_path or ""),
            "missing": list(result.missing),
            "summary_files": [str(path) for path in result.summary_files],
            "qc": result.qc,
        }
        _write_json(result_path, payload)
        progress("completed", 1.0, "报告生成与 QC 已完成")
        return 0
    except Exception as exc:  # noqa: BLE001
        _write_json(result_path, {
            "schema_version": 1,
            "state": "failed",
            "error": str(exc),
            "traceback": traceback.format_exc(),
        })
        _write_json(status_path, {
            "schema_version": 1,
            "state": "failed",
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
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    return run_context(args.job_context.resolve(), args.status.resolve(), args.result.resolve())


if __name__ == "__main__":
    raise SystemExit(main())
