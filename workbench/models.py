from __future__ import annotations

import hashlib
import json
import uuid
from dataclasses import asdict, dataclass, field
from datetime import date, datetime
from pathlib import Path
from typing import Any

from .version import app_version


SCHEMA_VERSION = 2
READABLE_SCHEMA_VERSIONS = {1, SCHEMA_VERSION}
TERMINAL_ANALYSIS_STATES = {"completed", "failed", "stopped", "launch_failed"}


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest().upper()


def _iso_date(value: str) -> str:
    return date.fromisoformat(str(value)).isoformat()


@dataclass
class AnalysisState:
    state: str = "draft"
    request_path: str = ""
    status_path: str = ""
    stop_path: str = ""
    stdout_log: str = ""
    stderr_log: str = ""
    manifest_path: str = ""
    manifest_sha256: str = ""
    executor_type: str = ""
    executable: str = ""
    pid: int | None = None


@dataclass
class ReportState:
    state: str = "blocked"
    report_type: str = ""
    template_path: str = ""
    template_sha256: str = ""
    output_dir: str = ""
    manifest_path: str = ""
    derived_artifact_manifest_path: str = ""
    derived_artifact_manifest_sha256: str = ""
    plots_approved: bool = False
    stdout_log: str = ""
    stderr_log: str = ""
    status_path: str = ""
    result_path: str = ""
    output_docx: str = ""
    output_pdf: str = ""
    qc_state: str = ""
    visual_qc_dir: str = ""
    visual_contact_sheet: str = ""
    pid: int | None = None


@dataclass
class JobContext:
    schema_version: int
    job_id: str
    created_at: str
    updated_at: str
    app_version: str
    project_root: str
    bridge_id: str
    bridge_name: str
    data_root: str
    start_date: str
    end_date: str
    config_path: str
    config_sha256: str
    selected_modules: list[str] = field(default_factory=list)
    options: dict[str, bool] = field(default_factory=dict)
    period_label: str = ""
    monitoring_range: str = ""
    report_date: str = ""
    analysis: AnalysisState = field(default_factory=AnalysisState)
    report: ReportState = field(default_factory=ReportState)

    @classmethod
    def create(
        cls,
        *,
        project_root: Path,
        bridge_id: str,
        bridge_name: str,
        data_root: Path,
        start_date: str,
        end_date: str,
        config_path: Path,
        selected_modules: list[str],
        options: dict[str, bool],
        report_type: str = "",
        template_path: Path | None = None,
        output_dir: Path | None = None,
        period_label: str = "",
        monitoring_range: str = "",
        report_date: str = "",
        now: datetime | None = None,
        job_id: str | None = None,
    ) -> "JobContext":
        now = now or datetime.now().astimezone()
        start = _iso_date(start_date)
        end = _iso_date(end_date)
        if end < start:
            raise ValueError("end_date must be on or after start_date")
        config_path = config_path.expanduser().resolve()
        if not config_path.is_file():
            raise FileNotFoundError(f"Config file does not exist: {config_path}")
        data_root = data_root.expanduser().resolve()
        run_id = job_id or f"{bridge_id}_{now:%Y%m%d_%H%M%S}_{uuid.uuid4().hex[:6]}"
        job_dir = data_root / "run_logs" / "workbench" / run_id
        analysis = AnalysisState(
            request_path=str(job_dir / "run_request.json"),
            status_path=str(job_dir / "analysis_status.json"),
            stop_path=str(job_dir / "stop.flag"),
            stdout_log=str(job_dir / "analysis_stdout.log"),
            stderr_log=str(job_dir / "analysis_stderr.log"),
        )
        report = ReportState(
            report_type=report_type,
            template_path=str(template_path.resolve()) if template_path else "",
            template_sha256=file_sha256(template_path.resolve()) if template_path and template_path.is_file() else "",
            output_dir=str((output_dir or (data_root / "自动报告")).resolve()),
            stdout_log=str(job_dir / "report_stdout.log"),
            stderr_log=str(job_dir / "report_stderr.log"),
            status_path=str(job_dir / "report_status.json"),
            result_path=str(job_dir / "report_result.json"),
        )
        stamp = now.isoformat(timespec="seconds")
        from .config_layers import config_dependency_sha256

        return cls(
            schema_version=SCHEMA_VERSION,
            job_id=run_id,
            created_at=stamp,
            updated_at=stamp,
            app_version=app_version(project_root),
            project_root=str(project_root.resolve()),
            bridge_id=bridge_id,
            bridge_name=bridge_name,
            data_root=str(data_root),
            start_date=start,
            end_date=end,
            config_path=str(config_path),
            config_sha256=config_dependency_sha256(config_path),
            selected_modules=list(dict.fromkeys(selected_modules)),
            options=dict(options),
            period_label=period_label,
            monitoring_range=monitoring_range,
            report_date=report_date,
            analysis=analysis,
            report=report,
        )

    @property
    def context_path(self) -> Path:
        return Path(self.analysis.request_path).with_name("job_context.json")

    @property
    def analysis_terminal(self) -> bool:
        return self.analysis.state.lower() in TERMINAL_ANALYSIS_STATES

    @property
    def report_ready(self) -> bool:
        return (
            self.analysis.state.lower() == "completed"
            and bool(self.analysis.manifest_path)
            and bool(self.selected_modules)
            and self.report.plots_approved
        )

    def touch(self) -> None:
        self.updated_at = datetime.now().astimezone().isoformat(timespec="seconds")

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)

    def write(self, path: Path | None = None) -> Path:
        target = path or self.context_path
        target.parent.mkdir(parents=True, exist_ok=True)
        self.touch()
        target.write_text(json.dumps(self.to_dict(), ensure_ascii=False, indent=2), encoding="utf-8")
        return target

    @classmethod
    def from_dict(cls, raw: dict[str, Any]) -> "JobContext":
        payload = dict(raw)
        source_version = int(payload.get("schema_version", 0))
        if source_version not in READABLE_SCHEMA_VERSIONS:
            raise ValueError(f"Unsupported job context schema: {payload.get('schema_version')}")
        payload["schema_version"] = SCHEMA_VERSION
        payload["analysis"] = AnalysisState(**payload.get("analysis", {}))
        payload["report"] = ReportState(**payload.get("report", {}))
        context = cls(**payload)
        _iso_date(context.start_date)
        _iso_date(context.end_date)
        return context

    @classmethod
    def read(cls, path: Path) -> "JobContext":
        return cls.from_dict(json.loads(path.read_text(encoding="utf-8-sig")))
