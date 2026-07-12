from __future__ import annotations

import argparse
import hashlib
import json
import os
import traceback
from datetime import datetime
from pathlib import Path
from typing import Any

from report_job import ReportJobRequest, execute_report_job


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest().upper()


def _write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + f".{os.getpid()}.tmp")
    temporary.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    temporary.replace(path)


def _verify_file(label: str, value: object, expected: object) -> Path:
    path = Path(str(value or "")).expanduser().resolve()
    if not path.is_file():
        raise FileNotFoundError(f"{label} does not exist: {path}")
    if expected and _sha256(path) != str(expected).upper():
        raise RuntimeError(f"{label} changed after workbench approval: {path}")
    return path


def request_from_context(path: Path) -> ReportJobRequest:
    payload = json.loads(path.read_text(encoding="utf-8-sig"))
    if not isinstance(payload, dict) or int(payload.get("schema_version", 0)) != 1:
        raise ValueError("unsupported workbench job context")
    analysis = payload.get("analysis") if isinstance(payload.get("analysis"), dict) else {}
    report = payload.get("report") if isinstance(payload.get("report"), dict) else {}
    if not report.get("plots_approved"):
        raise RuntimeError("plot review gate is not approved")
    if str(analysis.get("state") or "").lower() != "completed":
        raise RuntimeError("analysis is not completed")
    _verify_file("analysis manifest", analysis.get("manifest_path"), analysis.get("manifest_sha256"))
    template = _verify_file("report template", report.get("template_path"), report.get("template_sha256"))
    config = _verify_file("config", payload.get("config_path"), payload.get("config_sha256"))
    result_root = Path(str(payload.get("data_root") or "")).expanduser().resolve()
    output_dir = Path(str(report.get("output_dir") or result_root / "自动报告")).expanduser().resolve()
    project_root = Path(str(payload.get("project_root") or Path.cwd())).expanduser().resolve()
    report_type = str(report.get("report_type") or "").strip()
    wim_root = result_root / "WIM" / "results" / "hongtang" if report_type == "hongtang_period_wim" else None
    return ReportJobRequest(
        report_type=report_type,
        template=template,
        config_path=config,
        result_root=result_root,
        analysis_root=project_root,
        output_dir=output_dir,
        period_label=str(payload.get("period_label") or ""),
        monitoring_range=str(payload.get("monitoring_range") or ""),
        report_date=str(payload.get("report_date") or ""),
        start_date=str(payload.get("start_date") or ""),
        end_date=str(payload.get("end_date") or ""),
        wim_root=wim_root,
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
