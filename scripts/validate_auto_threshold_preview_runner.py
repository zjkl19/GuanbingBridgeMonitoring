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

from workbench.auto_threshold import (
    launch,
    load_preview_artifact,
    load_result,
    prepare_request,
    read_status,
)


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Validate compiled automatic-cleaning preview contract")
    parser.add_argument("--project-root", type=Path, default=Path.cwd())
    parser.add_argument("--output-root", type=Path, required=True)
    parser.add_argument("--replace", action="store_true")
    return parser


def main() -> int:
    args = _parser().parse_args()
    project_root = args.project_root.resolve()
    output_root = args.output_root.resolve()
    if output_root.exists():
        if not args.replace:
            raise SystemExit(f"output root already exists: {output_root}")
        shutil.rmtree(output_root)
    data_root = output_root / "data"
    feature_root = data_root / "2026-01-01" / "features"
    feature_root.mkdir(parents=True)
    rows = []
    base = datetime(2026, 1, 1)
    for index in range(100):
        rows.append(f"{(base + timedelta(minutes=index)):%Y-%m-%d %H:%M:%S},{math.sin(index / 8) * 5:.6f}")
    rows.append(f"{(base + timedelta(minutes=100)):%Y-%m-%d %H:%M:%S},100.000000")
    (feature_root / "T-1.csv").write_text("\n".join(rows) + "\n", encoding="utf-8")

    config_path = output_root / "config.json"
    config_path.write_text(
        json.dumps(
            {
                "vendor": "donghua",
                "defaults": {
                    "header_marker": "__no_header__",
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
    paths, payload = prepare_request(
        data_root=data_root,
        config_path=config_path,
        start_date="2026-01-01",
        end_date="2026-01-01",
        request_id="compiled_preview_contract",
        options={
            "module_keys": ["temperature"],
            "capture_preview_series": True,
            "preview_sample_count": 32,
            "use_auto_cut": False,
            "use_quantile": True,
            "quantile_low": 0,
            "quantile_high": 95,
            "padding_factor": 0,
            "use_mad": False,
            "use_iqr": False,
            "use_spike_window": False,
            "use_zero_or_flat": False,
            "min_valid_count": 20,
            "max_removed_ratio": 0.2,
        },
    )
    run = launch(project_root, paths, str(payload["config_sha256"]))
    exit_code = run.process.wait(timeout=180)
    status = read_status(paths.status)
    if exit_code != 0 or status.get("status") != "completed":
        raise SystemExit(
            f"compiled preview runner failed: exit={exit_code} status={status} stderr={paths.stderr}"
        )
    result = load_result(paths.result)
    previews = load_preview_artifact(
        Path(result["preview_path"]),
        expected_sha256=str(result["preview_sha256"]),
        expected_request_id=str(result["request_id"]),
        expected_config_sha256=str(result["config_sha256"]),
        expected_series_count=int(result["preview_series_count"]),
    )
    proposals = result.get("proposals") or []
    series = previews.get(("temperature", "T-1"))
    if not proposals or series is None:
        raise SystemExit("compiled runner did not produce proposal and matching preview series")
    finite = [value for value in series.values if value is not None]
    if len(series.values) > 32 or not finite or max(finite) != 100:
        raise SystemExit("preview sampling did not preserve the source maximum within the requested cap")
    summary = {
        "ok": True,
        "runner_exit_code": exit_code,
        "request_id": result["request_id"],
        "config_sha256": result["config_sha256"],
        "preview_sha256": result["preview_sha256"],
        "proposal_count": len(proposals),
        "preview_series_count": len(previews),
        "preview_sample_count": len(series.values),
        "preview_max": max(finite),
        "status_path": str(paths.status),
        "result_path": str(paths.result),
        "preview_path": str(paths.preview),
    }
    summary_path = output_root / "preview_contract_summary.json"
    summary_path.write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
