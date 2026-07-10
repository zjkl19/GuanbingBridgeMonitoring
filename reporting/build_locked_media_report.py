from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

try:
    from locked_docx_media import (
        LockedDocxMediaError,
        apply_media_plan,
        inventory_docx,
        inventory_to_dict,
        patch_audit_to_dict,
        validate_media_plan,
        validation_report_to_dict,
    )
    from report_media_plan import (
        MediaPlanError,
        compile_media_plan,
        load_explicit_bindings,
        load_media_plan,
        media_plan_to_dict,
        write_media_plan,
    )
except ImportError:  # pragma: no cover - package import fallback
    from .locked_docx_media import (
        LockedDocxMediaError,
        apply_media_plan,
        inventory_docx,
        inventory_to_dict,
        patch_audit_to_dict,
        validate_media_plan,
        validation_report_to_dict,
    )
    from .report_media_plan import (
        MediaPlanError,
        compile_media_plan,
        load_explicit_bindings,
        load_media_plan,
        media_plan_to_dict,
        write_media_plan,
    )


def _write_json(path: Path | None, payload: dict[str, Any]) -> None:
    text = json.dumps(payload, ensure_ascii=False, indent=2) + "\n"
    if path is None:
        sys.stdout.write(text)
        return
    output_path = path.expanduser().resolve()
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(text, encoding="utf-8")
    print(output_path)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Strictly replace approved DOCX media members without saving through python-docx."
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    inventory_parser = subparsers.add_parser("inventory", help="Inventory baseline media and OOXML references.")
    inventory_parser.add_argument("--baseline", type=Path, required=True)
    inventory_parser.add_argument("--output", type=Path, default=None)

    plan_parser = subparsers.add_parser("plan", help="Compile an immutable plan from explicit member/path bindings.")
    plan_parser.add_argument("--baseline", type=Path, required=True)
    plan_parser.add_argument("--bindings", type=Path, required=True)
    plan_parser.add_argument("--output", type=Path, required=True)
    plan_parser.add_argument("--expected-baseline-sha256", default="")
    plan_parser.add_argument("--analysis-manifest", type=Path, default=None)

    validate_parser = subparsers.add_parser("validate", help="Revalidate baseline, candidates, hashes, and sizes.")
    validate_parser.add_argument("--plan", type=Path, required=True)
    validate_parser.add_argument("--output", type=Path, default=None)

    apply_parser = subparsers.add_parser("apply", help="Atomically create a media-only patched DOCX.")
    apply_parser.add_argument("--plan", type=Path, required=True)
    apply_parser.add_argument("--output", type=Path, required=True)
    apply_parser.add_argument("--overwrite", action="store_true")
    apply_parser.add_argument("--audit-output", type=Path, default=None)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        if args.command == "inventory":
            _write_json(args.output, inventory_to_dict(inventory_docx(args.baseline)))
            return 0
        if args.command == "plan":
            plan = compile_media_plan(
                args.baseline,
                load_explicit_bindings(args.bindings),
                expected_baseline_sha256=args.expected_baseline_sha256,
                analysis_manifest_path=args.analysis_manifest,
            )
            write_media_plan(plan, args.output)
            return 0
        if args.command == "validate":
            plan = load_media_plan(args.plan)
            _write_json(args.output, validation_report_to_dict(validate_media_plan(plan)))
            return 0
        if args.command == "apply":
            plan = load_media_plan(args.plan)
            audit = apply_media_plan(plan, args.output, overwrite=args.overwrite)
            _write_json(args.audit_output, patch_audit_to_dict(audit))
            return 0
        raise MediaPlanError(f"Unsupported command: {args.command}")
    except (LockedDocxMediaError, MediaPlanError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
