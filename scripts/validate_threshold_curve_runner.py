from __future__ import annotations

import argparse
import json
import math
import shutil
import sys
from datetime import datetime, timedelta
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from workbench.threshold_curve import (
    launch,
    load_current_threshold_curve,
    load_result,
    prepare_threshold_curve_request,
    read_status,
)


_MARKER_NAME = ".guanbing-threshold-curve-smoke-root.json"


def _prepare_output_root(output_root: Path, *, replace: bool) -> None:
    marker = output_root / _MARKER_NAME
    if output_root.exists():
        if not replace:
            raise RuntimeError(f"output root already exists: {output_root}")
        if not marker.is_file():
            raise RuntimeError(
                "refusing to replace an unmarked threshold-curve smoke root: "
                f"{output_root}"
            )
        shutil.rmtree(output_root)
    output_root.mkdir(parents=True)
    marker.write_text(
        json.dumps(
            {
                "schema_version": 1,
                "artifact_type": "threshold_curve_runner_smoke_root",
            },
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Validate compiled independent threshold-curve contract"
    )
    parser.add_argument("--project-root", type=Path, default=Path.cwd())
    parser.add_argument("--output-root", type=Path, required=True)
    parser.add_argument("--replace", action="store_true")
    return parser


def main() -> int:
    args = _parser().parse_args()
    project_root = args.project_root.resolve()
    output_root = args.output_root.resolve()
    _prepare_output_root(output_root, replace=args.replace)
    data_root = output_root / "data"
    feature_root = data_root / "2026-01-01" / "features"
    feature_root.mkdir(parents=True)
    base = datetime(2026, 1, 1)
    rows = [
        f"{(base + timedelta(minutes=index)):%Y-%m-%d %H:%M:%S},{math.sin(index / 8) * 5:.6f}"
        for index in range(100)
    ]
    rows.append(
        f"{(base + timedelta(minutes=100)):%Y-%m-%d %H:%M:%S},100.000000"
    )
    (feature_root / "T-1.csv").write_text("\n".join(rows) + "\n", encoding="utf-8")

    config_path = output_root / "config.json"
    config_path.write_text(
        json.dumps(
            {
                "bridge_id": "compiled_curve_contract",
                "vendor": "donghua",
                "defaults": {
                    "header_marker": "__no_header__",
                    # The independent curve must ignore this restrictive rule.
                    "temperature": {"thresholds": {"min": -1, "max": 1}},
                },
                "points": {"temperature": ["T-1"]},
                "subfolders": {"temperature": "features"},
                "file_patterns": {
                    "temperature": {"default": ["{point}.csv"], "per_point": {}}
                },
                "per_point": {},
            },
            ensure_ascii=False,
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    paths, payload = prepare_threshold_curve_request(
        bridge_id="compiled_curve_contract",
        data_root=data_root,
        config_path=config_path,
        start_date="2026-01-01",
        end_date="2026-01-01",
        module_key="temperature",
        point_id="T-1",
        request_id="compiled_curve_contract",
    )
    run = launch(project_root, paths, str(payload["config_sha256"]))
    exit_code = run.process.wait(timeout=180)
    status = read_status(paths.status, expected_request_id=run.request_id)
    if exit_code != 0 or status.get("status") != "completed":
        raise SystemExit(
            f"compiled curve runner failed: exit={exit_code} status={status} stderr={paths.stderr}"
        )
    result = load_result(
        paths.result,
        expected_request_id=run.request_id,
        expected_config_sha256=run.config_sha256,
    )
    previews = load_current_threshold_curve(
        Path(result["preview_path"]),
        expected_bridge_id=run.bridge_id,
        expected_data_root=run.data_root,
        expected_start_date=run.start_date,
        expected_end_date=run.end_date,
        expected_config_sha256=run.config_sha256,
        expected_module_key=run.module_key,
        expected_point_ids=(run.point_id,),
    )
    series = previews.get(("temperature", "T-1"))
    metadata = result["record_metadata"]
    finite = [value for value in series.values if value is not None] if series else []
    if series is None or not finite or max(finite) != 100:
        raise SystemExit("independent curve did not preserve values outside existing cleaning rules")
    if metadata.source_sample_count != 101 or metadata.finite_sample_count != 101:
        raise SystemExit("independent curve source/finite counts are not closed")
    if list(paths.root.glob("auto_threshold_preview*.json")):
        raise SystemExit("independent curve task emitted a legacy Beta preview")
    if float(status.get("progress_percent") or 0) != 100:
        raise SystemExit("independent curve task did not close real progress at 100 percent")
    summary = {
        "ok": True,
        "runner_exit_code": exit_code,
        "request_id": result["request_id"],
        "config_sha256": result["config_sha256"],
        "preview_sha256": result["preview_sha256"],
        "record_sha256": result["record_sha256"],
        "curve_record_count": len(previews),
        "source_sample_count": metadata.source_sample_count,
        "finite_sample_count": metadata.finite_sample_count,
        "preview_sample_count": metadata.sample_count,
        "preview_max": max(finite),
        "progress_percent": float(status["progress_percent"]),
        "unexpected_auto_preview_count": 0,
        "status_path": str(paths.status),
        "result_path": str(paths.result),
        "preview_path": str(paths.preview),
        "record_path": str(paths.record),
    }
    summary_path = output_root / "threshold_curve_contract_summary.json"
    summary_path.write_text(
        json.dumps(summary, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
