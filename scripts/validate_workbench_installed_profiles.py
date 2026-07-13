from __future__ import annotations

import argparse
import json
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from workbench.models import file_sha256  # noqa: E402
from workbench.profiles import WorkbenchProfile, load_profiles  # noqa: E402


SUPPORTED_REPORT_TYPES = {
    "guanbing_monthly",
    "hongtang_period_wim",
    "jlj_monthly",
    "shuixianhua_monthly",
    "zhishan_monthly",
}


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Validate every bridge profile in the frozen workbench")
    parser.add_argument("--package-root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--evidence-root", type=Path, default=None)
    parser.add_argument("--timeout-seconds", type=int, default=60)
    return parser


def _asset_paths(package_root: Path, profiles: list[WorkbenchProfile]) -> tuple[Path, ...]:
    assets = {package_root / "config" / "bridge_profiles.json"}
    for profile in profiles:
        assets.add(profile.config_path(package_root))
        if profile.report_template:
            assets.add(profile.template_path(package_root))
    return tuple(sorted((path.resolve() for path in assets), key=lambda path: str(path).casefold()))


def _hash_snapshot(paths: tuple[Path, ...]) -> dict[str, str]:
    missing = [str(path) for path in paths if not path.is_file()]
    if missing:
        raise RuntimeError(f"packaged profile asset(s) missing: {missing}")
    return {str(path): file_sha256(path) for path in paths}


def validate_profile_payload(
    profile: WorkbenchProfile,
    payload: dict[str, Any],
    package_root: Path,
) -> dict[str, Any]:
    expected_config = profile.config_path(package_root)
    expected_template = profile.template_path(package_root) if profile.report_template else None
    expected_report_capable = bool(profile.report_template and profile.report_gui_type)
    checks = {
        "ok": payload.get("ok") is True,
        "profile_id": payload.get("selected_profile_id") == profile.bridge_id,
        "profile_name": payload.get("selected_profile_name") == profile.bridge_name,
        "data_layout": payload.get("selected_data_layout") == profile.data_layout,
        "report_type": payload.get("selected_report_type") == profile.report_type,
        "report_gui_type": payload.get("selected_report_gui_type") == profile.report_gui_type,
        "report_capable": payload.get("selected_report_capable") is expected_report_capable,
        "data_root": payload.get("selected_data_root") == profile.default_data_root,
        "dates": (
            payload.get("selected_start_date") == profile.default_start_date
            and payload.get("selected_end_date") == profile.default_end_date
        ),
        "modules": (
            set(payload.get("selected_modules") or []) == set(profile.enabled_modules)
            and len(payload.get("selected_modules") or []) == len(profile.enabled_modules)
        ),
        "config_path": Path(str(payload.get("selected_config_path") or "")).resolve() == expected_config,
        "config_sha256": payload.get("selected_config_sha256") == file_sha256(expected_config),
        "template_path": (
            Path(str(payload.get("selected_template_path") or "")).resolve() == expected_template
            if expected_template
            else not payload.get("selected_template_path")
        ),
        "template_sha256": (
            payload.get("selected_template_sha256") == file_sha256(expected_template)
            if expected_template
            else not payload.get("selected_template_sha256")
        ),
        "config_load": not payload.get("configuration_load_errors"),
        "workflow_shape": (
            payload.get("profile_count") == 6
            and payload.get("tab_count") == 4
            and payload.get("config_tab_count") == 8
            and payload.get("warning_subtab_count") == 2
            and payload.get("module_count") == 25
            and payload.get("plot_common_field_count") == 14
            and payload.get("spectrum_module_count") == 2
            and int(payload.get("effective_warning_row_count") or 0) > 0
            and int(payload.get("invalid_warning_row_count") or 0) == 0
            and payload.get("report_gate_locked") is True
        ),
    }
    failed = [name for name, passed in checks.items() if not passed]
    if failed:
        raise RuntimeError(f"frozen profile {profile.bridge_id} failed checks: {failed}; payload={payload}")
    return {
        "bridge_id": profile.bridge_id,
        "bridge_name": profile.bridge_name,
        "config_path": str(expected_config),
        "config_sha256": str(payload["selected_config_sha256"]),
        "template_path": str(expected_template) if expected_template else "",
        "template_sha256": str(payload.get("selected_template_sha256") or ""),
        "report_capable": expected_report_capable,
        "report_gui_type": profile.report_gui_type,
        "enabled_module_count": len(profile.enabled_modules),
        "alarm_bound_row_count": int(payload.get("alarm_bound_row_count") or 0),
        "effective_warning_row_count": int(payload.get("effective_warning_row_count") or 0),
        "invalid_warning_row_count": int(payload.get("invalid_warning_row_count") or 0),
        "cleaning_threshold_row_count": int(payload.get("cleaning_threshold_row_count") or 0),
        "offset_correction_row_count": int(payload.get("offset_correction_row_count") or 0),
        "group_plot_module_count": int(payload.get("group_plot_module_count") or 0),
        "checks": checks,
    }


def main() -> int:
    args = _parser().parse_args()
    package_root = args.package_root.resolve()
    executable = package_root / "BridgeMonitoringWorkbench.exe"
    if not executable.is_file():
        raise SystemExit(f"workbench executable missing: {executable}")
    profiles = load_profiles(package_root)
    if len(profiles) != 6 or len({profile.bridge_id for profile in profiles}) != 6:
        raise SystemExit("packaged bridge profile catalog must contain six unique profiles")
    report_types = {profile.report_gui_type for profile in profiles if profile.report_gui_type}
    if report_types != SUPPORTED_REPORT_TYPES:
        raise SystemExit(f"packaged report capability set differs: {sorted(report_types)}")
    assets = _asset_paths(package_root, profiles)
    before = _hash_snapshot(assets)
    output = args.output.resolve()
    evidence_root = (
        args.evidence_root.resolve()
        if args.evidence_root is not None
        else output.parent / f".{output.stem}_profiles"
    )
    evidence_root.mkdir(parents=True, exist_ok=True)
    rows = []
    started = time.monotonic()
    for profile in profiles:
        smoke_path = evidence_root / f"{profile.bridge_id}.json"
        process = subprocess.run(
            [
                str(executable),
                "--profile-id",
                profile.bridge_id,
                "--smoke-test",
                "--smoke-output",
                str(smoke_path),
            ],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=args.timeout_seconds,
            check=False,
        )
        if process.returncode != 0 or not smoke_path.is_file():
            raise SystemExit(
                f"frozen profile smoke failed: {profile.bridge_id}, exit={process.returncode}, output={smoke_path}"
            )
        payload = json.loads(smoke_path.read_text(encoding="utf-8-sig"))
        rows.append(validate_profile_payload(profile, payload, package_root))
    after = _hash_snapshot(assets)
    if before != after:
        changed = [path for path in before if before.get(path) != after.get(path)]
        raise SystemExit(f"frozen profile matrix modified packaged asset(s): {changed}")
    result = {
        "schema_version": 1,
        "status": "passed",
        "package_root": str(package_root),
        "executable_sha256": file_sha256(executable),
        "profile_count": len(rows),
        "report_capable_count": sum(row["report_capable"] for row in rows),
        "analysis_only_count": sum(not row["report_capable"] for row in rows),
        "asset_count": len(assets),
        "assets_unchanged": before == after,
        "elapsed_seconds": round(time.monotonic() - started, 3),
        "profiles": rows,
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
