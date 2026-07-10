from __future__ import annotations

import json
import math
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable, Mapping

try:
    from locked_docx_media import (
        DEFAULT_MAX_ASPECT_RATIO_ERROR,
        IMAGE_DIMENSION_POLICIES,
        IMAGE_DIMENSION_POLICY_EXACT,
        BaselineMismatchError,
        ImageInfo,
        LockedMediaPlan,
        MediaCandidateError,
        MediaMemberError,
        MediaReplacement,
        SharedMediaReferenceError,
        expected_plot_provenance_path,
        inventory_docx,
        manifest_artifact_record_for_paths,
        read_image_info,
        sha256_file,
        validate_full_plot_provenance,
        validate_image_compatibility,
    )
except ImportError:  # pragma: no cover - package import fallback
    from .locked_docx_media import (
        DEFAULT_MAX_ASPECT_RATIO_ERROR,
        IMAGE_DIMENSION_POLICIES,
        IMAGE_DIMENSION_POLICY_EXACT,
        BaselineMismatchError,
        ImageInfo,
        LockedMediaPlan,
        MediaCandidateError,
        MediaMemberError,
        MediaReplacement,
        SharedMediaReferenceError,
        expected_plot_provenance_path,
        inventory_docx,
        manifest_artifact_record_for_paths,
        read_image_info,
        sha256_file,
        validate_full_plot_provenance,
        validate_image_compatibility,
    )


SCHEMA_VERSION = 2
SUPPORTED_SCHEMA_VERSIONS = frozenset({1, SCHEMA_VERSION})
ACCEPTED_MANIFEST_STATUSES = frozenset({"ok", "completed", "complete", "success", "succeeded"})


class MediaPlanError(RuntimeError):
    """Invalid explicit binding or serialized media plan."""


@dataclass(frozen=True)
class ExplicitMediaBinding:
    slot_id: str
    member: str
    candidate_path: Path
    expected_original_sha256: str = ""
    expected_candidate_sha256: str = ""
    expected_format: str = ""
    expected_width_px: int | None = None
    expected_height_px: int | None = None
    dimension_policy: str = IMAGE_DIMENSION_POLICY_EXACT
    max_aspect_ratio_error: float = DEFAULT_MAX_ASPECT_RATIO_ERROR


def _normalize_format(value: str) -> str:
    text = str(value or "").upper().strip()
    if text == "JPG":
        return "JPEG"
    return text


def _normalize_dimension_policy(value: Any) -> str:
    policy = str(value or IMAGE_DIMENSION_POLICY_EXACT).strip().lower()
    if policy not in IMAGE_DIMENSION_POLICIES:
        raise MediaPlanError(
            f"Unsupported image dimension policy: {policy or '<missing>'}. "
            f"Expected one of: {', '.join(sorted(IMAGE_DIMENSION_POLICIES))}."
        )
    return policy


def _normalize_aspect_ratio_error(value: Any) -> float:
    if isinstance(value, bool):
        raise MediaPlanError("max_aspect_ratio_error must be numeric, not boolean.")
    try:
        tolerance = float(
            DEFAULT_MAX_ASPECT_RATIO_ERROR if value is None else value
        )
    except (TypeError, ValueError) as exc:
        raise MediaPlanError(f"Invalid max_aspect_ratio_error: {value}") from exc
    if not math.isfinite(tolerance) or tolerance < 0 or tolerance > 0.01:
        raise MediaPlanError(
            f"max_aspect_ratio_error must be between 0 and 0.01; got {tolerance}."
        )
    return tolerance


def _coerce_binding(value: ExplicitMediaBinding | Mapping[str, Any]) -> ExplicitMediaBinding:
    if isinstance(value, ExplicitMediaBinding):
        return value
    if not isinstance(value, Mapping):
        raise MediaPlanError(f"Binding must be an object, got: {type(value).__name__}")
    slot_id = str(value.get("slot_id") or "").strip()
    member = str(value.get("member") or "").strip()
    candidate_value = value.get("candidate_path", value.get("candidate"))
    if not slot_id:
        raise MediaPlanError("Each explicit binding requires a non-empty slot_id.")
    if not member:
        raise MediaPlanError(f"Binding {slot_id} requires a non-empty member.")
    if candidate_value is None or not str(candidate_value).strip():
        raise MediaPlanError(f"Binding {slot_id} requires a candidate_path.")
    try:
        width_value = value.get("expected_width_px")
        height_value = value.get("expected_height_px")
        expected_width = int(width_value) if width_value is not None else None
        expected_height = int(height_value) if height_value is not None else None
    except (TypeError, ValueError) as exc:
        raise MediaPlanError(f"Binding {slot_id} has an invalid expected pixel dimension.") from exc
    return ExplicitMediaBinding(
        slot_id=slot_id,
        member=member,
        candidate_path=Path(str(candidate_value)),
        expected_original_sha256=str(value.get("expected_original_sha256") or "").strip(),
        expected_candidate_sha256=str(value.get("expected_candidate_sha256") or "").strip(),
        expected_format=_normalize_format(str(value.get("expected_format") or "")),
        expected_width_px=expected_width,
        expected_height_px=expected_height,
        dimension_policy=_normalize_dimension_policy(value.get("dimension_policy")),
        max_aspect_ratio_error=_normalize_aspect_ratio_error(
            value.get("max_aspect_ratio_error")
        ),
    )


def _resolve_binding_paths(
    bindings: Iterable[ExplicitMediaBinding | Mapping[str, Any]],
    base_dir: Path | None = None,
) -> list[ExplicitMediaBinding]:
    resolved: list[ExplicitMediaBinding] = []
    for raw_binding in bindings:
        binding = _coerce_binding(raw_binding)
        candidate_path = binding.candidate_path.expanduser()
        if base_dir is not None and not candidate_path.is_absolute():
            candidate_path = base_dir / candidate_path
        resolved.append(
            ExplicitMediaBinding(
                slot_id=binding.slot_id,
                member=binding.member,
                candidate_path=candidate_path.resolve(),
                expected_original_sha256=binding.expected_original_sha256,
                expected_candidate_sha256=binding.expected_candidate_sha256,
                expected_format=binding.expected_format,
                expected_width_px=binding.expected_width_px,
                expected_height_px=binding.expected_height_px,
                dimension_policy=_normalize_dimension_policy(binding.dimension_policy),
                max_aspect_ratio_error=_normalize_aspect_ratio_error(
                    binding.max_aspect_ratio_error
                ),
            )
        )
    return resolved


def load_explicit_bindings(path: Path | str) -> list[ExplicitMediaBinding]:
    bindings_path = Path(path).expanduser().resolve()
    try:
        payload = json.loads(bindings_path.read_text(encoding="utf-8-sig"))
    except (OSError, json.JSONDecodeError) as exc:
        raise MediaPlanError(f"Unable to load explicit bindings JSON: {bindings_path}: {exc}") from exc
    records = payload.get("bindings") if isinstance(payload, dict) else payload
    if not isinstance(records, list):
        raise MediaPlanError("Bindings JSON must be a list or an object containing a bindings list.")
    return _resolve_binding_paths(records, bindings_path.parent)


def _load_explicit_manifest(
    path: Path | str | None,
) -> tuple[Path | None, str, str, dict[str, Any] | None]:
    if path is None:
        return None, "", "", None
    manifest_path = Path(path).expanduser().resolve()
    if not manifest_path.exists() or not manifest_path.is_file():
        raise MediaPlanError(f"Explicit analysis manifest does not exist: {manifest_path}")
    try:
        payload = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
    except (OSError, json.JSONDecodeError) as exc:
        raise MediaPlanError(f"Unable to load explicit analysis manifest: {manifest_path}: {exc}") from exc
    if not isinstance(payload, dict):
        raise MediaPlanError(f"Explicit analysis manifest must be a JSON object: {manifest_path}")
    status = str(payload.get("status") or "").lower().strip()
    if status not in ACCEPTED_MANIFEST_STATUSES:
        raise MediaPlanError(
            f"Explicit analysis manifest status is not accepted: {status or '<missing>'}: {manifest_path}"
        )
    return manifest_path, sha256_file(manifest_path), status, payload


def compile_media_plan(
    baseline_docx: Path | str,
    explicit_bindings: Iterable[ExplicitMediaBinding | Mapping[str, Any]],
    *,
    expected_baseline_sha256: str = "",
    analysis_manifest_path: Path | str | None = None,
) -> LockedMediaPlan:
    """Compile a strict plan from exact paths; no directory or mtime lookup occurs."""

    inventory = inventory_docx(baseline_docx)
    if expected_baseline_sha256 and inventory.sha256.lower() != expected_baseline_sha256.lower():
        raise BaselineMismatchError(
            f"Baseline SHA-256 mismatch: expected {expected_baseline_sha256}, got {inventory.sha256}"
        )
    bindings = _resolve_binding_paths(explicit_bindings)
    if not bindings:
        raise MediaPlanError("At least one explicit media binding is required.")

    slot_ids = [binding.slot_id for binding in bindings]
    members = [binding.member for binding in bindings]
    if len(slot_ids) != len(set(slot_ids)):
        raise MediaPlanError("Duplicate slot_id in explicit bindings.")
    if len(members) != len(set(members)):
        raise MediaPlanError("Duplicate media member in explicit bindings.")

    manifest_path, manifest_sha256, manifest_status, manifest_payload = _load_explicit_manifest(
        analysis_manifest_path
    )
    replacements: list[MediaReplacement] = []
    for binding in bindings:
        member = inventory.media.get(binding.member)
        if member is None:
            raise MediaMemberError(f"Baseline media member does not exist: {binding.member}")
        if binding.expected_original_sha256 and (
            member.sha256.lower() != binding.expected_original_sha256.lower()
        ):
            raise MediaMemberError(
                f"Baseline media SHA-256 mismatch for {binding.member}: "
                f"expected {binding.expected_original_sha256}, got {member.sha256}"
            )
        if member.reference_count != 1:
            raise SharedMediaReferenceError(
                f"Strict replacement requires exactly one OOXML reference for {binding.member}; "
                f"found {member.reference_count}."
            )
        if member.image_info is None:
            raise MediaMemberError(f"Baseline media is not a Pillow-readable raster image: {binding.member}")

        baseline_info = member.image_info
        expected_info = ImageInfo(
            binding.expected_format or baseline_info.format,
            binding.expected_width_px if binding.expected_width_px is not None else baseline_info.width_px,
            binding.expected_height_px if binding.expected_height_px is not None else baseline_info.height_px,
        )
        expected_info = ImageInfo(
            _normalize_format(expected_info.format), expected_info.width_px, expected_info.height_px
        )
        if baseline_info != expected_info:
            raise MediaMemberError(
                f"Baseline media does not match explicit slot expectations for {binding.member}: "
                f"expected {expected_info}, got {baseline_info}"
            )

        candidate_path = binding.candidate_path.expanduser().resolve()
        if not candidate_path.exists() or not candidate_path.is_file():
            raise MediaCandidateError(f"Explicit candidate image does not exist: {candidate_path}")
        candidate_sha256 = sha256_file(candidate_path)
        if binding.expected_candidate_sha256 and (
            candidate_sha256.lower() != binding.expected_candidate_sha256.lower()
        ):
            raise MediaCandidateError(
                f"Candidate SHA-256 mismatch for {candidate_path}: "
                f"expected {binding.expected_candidate_sha256}, got {candidate_sha256}"
            )
        candidate_info = read_image_info(candidate_path)
        validate_image_compatibility(
            baseline_info,
            candidate_info,
            dimension_policy=binding.dimension_policy,
            max_aspect_ratio_error=binding.max_aspect_ratio_error,
            candidate_label=str(candidate_path),
        )

        provenance_path: Path | None = None
        provenance_sha256 = ""
        provenance_series_count = 0
        manifest_artifact_record = ""
        if manifest_payload is not None:
            provenance_path = expected_plot_provenance_path(candidate_path)
            provenance_series_count = validate_full_plot_provenance(
                provenance_path, candidate_path
            )
            provenance_sha256 = sha256_file(provenance_path)
            manifest_artifact_record = manifest_artifact_record_for_paths(
                manifest_payload,
                candidate_path,
                provenance_path,
            )

        replacements.append(
            MediaReplacement(
                slot_id=binding.slot_id,
                member=binding.member,
                candidate_path=candidate_path,
                original_sha256=member.sha256,
                candidate_sha256=candidate_sha256,
                format=baseline_info.format,
                width_px=baseline_info.width_px,
                height_px=baseline_info.height_px,
                extents_emu=member.extents_emu,
                candidate_width_px=candidate_info.width_px,
                candidate_height_px=candidate_info.height_px,
                dimension_policy=binding.dimension_policy,
                max_aspect_ratio_error=binding.max_aspect_ratio_error,
                provenance_path=provenance_path,
                provenance_sha256=provenance_sha256,
                provenance_series_count=provenance_series_count,
                manifest_artifact_record=manifest_artifact_record,
            )
        )

    return LockedMediaPlan(
        baseline_path=inventory.path,
        baseline_sha256=inventory.sha256,
        replacements=tuple(replacements),
        source_manifest_path=manifest_path,
        source_manifest_sha256=manifest_sha256,
        source_manifest_status=manifest_status,
    )


def media_plan_to_dict(plan: LockedMediaPlan) -> dict[str, Any]:
    source_manifest: dict[str, Any] | None = None
    if plan.source_manifest_path is not None:
        source_manifest = {
            "path": str(plan.source_manifest_path),
            "sha256": plan.source_manifest_sha256,
            "status": plan.source_manifest_status,
        }
    return {
        "schema_version": SCHEMA_VERSION,
        "baseline": {
            "path": str(plan.baseline_path),
            "sha256": plan.baseline_sha256,
        },
        "source_manifest": source_manifest,
        "replacements": [
            {
                "slot_id": replacement.slot_id,
                "member": replacement.member,
                "candidate_path": str(replacement.candidate_path),
                "original_sha256": replacement.original_sha256,
                "candidate_sha256": replacement.candidate_sha256,
                "format": replacement.format,
                "width_px": replacement.width_px,
                "height_px": replacement.height_px,
                "candidate_width_px": replacement.candidate_width_px,
                "candidate_height_px": replacement.candidate_height_px,
                "dimension_policy": replacement.dimension_policy,
                "max_aspect_ratio_error": replacement.max_aspect_ratio_error,
                "extents_emu": [list(extent) for extent in replacement.extents_emu],
                "provenance_path": (
                    str(replacement.provenance_path)
                    if replacement.provenance_path is not None
                    else None
                ),
                "provenance_sha256": replacement.provenance_sha256,
                "provenance_series_count": replacement.provenance_series_count,
                "manifest_artifact_record": replacement.manifest_artifact_record,
            }
            for replacement in plan.replacements
        ],
    }


def write_media_plan(plan: LockedMediaPlan, path: Path | str) -> Path:
    output_path = Path(path).expanduser().resolve()
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(
        json.dumps(media_plan_to_dict(plan), ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    return output_path


def _resolve_serialized_path(value: Any, plan_dir: Path, label: str) -> Path:
    text = str(value or "").strip()
    if not text:
        raise MediaPlanError(f"Serialized media plan is missing {label}.")
    path = Path(text).expanduser()
    if not path.is_absolute():
        path = plan_dir / path
    return path.resolve()


def load_media_plan(path: Path | str) -> LockedMediaPlan:
    plan_path = Path(path).expanduser().resolve()
    try:
        payload = json.loads(plan_path.read_text(encoding="utf-8-sig"))
    except (OSError, json.JSONDecodeError) as exc:
        raise MediaPlanError(f"Unable to load media plan: {plan_path}: {exc}") from exc
    try:
        schema_version = int(payload.get("schema_version", 0)) if isinstance(payload, dict) else 0
    except (TypeError, ValueError):
        schema_version = 0
    if schema_version not in SUPPORTED_SCHEMA_VERSIONS:
        raise MediaPlanError(
            f"Unsupported media plan schema: "
            f"{payload.get('schema_version') if isinstance(payload, dict) else None}"
        )
    baseline = payload.get("baseline")
    if not isinstance(baseline, dict):
        raise MediaPlanError("Serialized media plan is missing baseline metadata.")
    baseline_path = _resolve_serialized_path(baseline.get("path"), plan_path.parent, "baseline.path")
    baseline_sha256 = str(baseline.get("sha256") or "").strip()
    if not baseline_sha256:
        raise MediaPlanError("Serialized media plan is missing baseline.sha256.")

    records = payload.get("replacements")
    if not isinstance(records, list) or not records:
        raise MediaPlanError("Serialized media plan requires at least one replacement.")
    replacements: list[MediaReplacement] = []
    for record in records:
        if not isinstance(record, dict):
            raise MediaPlanError("Serialized replacement must be an object.")
        extents_raw = record.get("extents_emu") or []
        try:
            extents = tuple((int(value[0]), int(value[1])) for value in extents_raw)
            width_px = int(record.get("width_px"))
            height_px = int(record.get("height_px"))
            if schema_version == 1:
                candidate_width_px = width_px
                candidate_height_px = height_px
                dimension_policy = IMAGE_DIMENSION_POLICY_EXACT
                max_aspect_ratio_error = DEFAULT_MAX_ASPECT_RATIO_ERROR
            else:
                candidate_width_px = int(record.get("candidate_width_px"))
                candidate_height_px = int(record.get("candidate_height_px"))
                dimension_policy = _normalize_dimension_policy(
                    record.get("dimension_policy")
                )
                max_aspect_ratio_error = _normalize_aspect_ratio_error(
                    record.get("max_aspect_ratio_error")
                )
                if candidate_width_px <= 0 or candidate_height_px <= 0:
                    raise ValueError("candidate dimensions must be positive")
            provenance_path_value = record.get("provenance_path")
            provenance_path = (
                _resolve_serialized_path(
                    provenance_path_value,
                    plan_path.parent,
                    "replacement.provenance_path",
                )
                if provenance_path_value is not None and str(provenance_path_value).strip()
                else None
            )
            replacement = MediaReplacement(
                slot_id=str(record.get("slot_id") or "").strip(),
                member=str(record.get("member") or "").strip(),
                candidate_path=_resolve_serialized_path(
                    record.get("candidate_path"), plan_path.parent, "replacement.candidate_path"
                ),
                original_sha256=str(record.get("original_sha256") or "").strip(),
                candidate_sha256=str(record.get("candidate_sha256") or "").strip(),
                format=_normalize_format(str(record.get("format") or "")),
                width_px=width_px,
                height_px=height_px,
                extents_emu=extents,
                candidate_width_px=candidate_width_px,
                candidate_height_px=candidate_height_px,
                dimension_policy=dimension_policy,
                max_aspect_ratio_error=max_aspect_ratio_error,
                provenance_path=provenance_path,
                provenance_sha256=str(record.get("provenance_sha256") or "").strip(),
                provenance_series_count=int(record.get("provenance_series_count") or 0),
                manifest_artifact_record=str(record.get("manifest_artifact_record") or "").strip(),
            )
        except (IndexError, TypeError, ValueError) as exc:
            raise MediaPlanError(f"Serialized replacement has invalid dimensions/extents: {record}") from exc
        if not all(
            (
                replacement.slot_id,
                replacement.member,
                replacement.original_sha256,
                replacement.candidate_sha256,
                replacement.format,
            )
        ):
            raise MediaPlanError(f"Serialized replacement is missing required values: {record}")
        replacements.append(replacement)

    source_manifest = payload.get("source_manifest")
    source_manifest_path: Path | None = None
    source_manifest_sha256 = ""
    source_manifest_status = ""
    if source_manifest is not None:
        if not isinstance(source_manifest, dict):
            raise MediaPlanError("source_manifest must be an object or null.")
        source_manifest_path = _resolve_serialized_path(
            source_manifest.get("path"), plan_path.parent, "source_manifest.path"
        )
        source_manifest_sha256 = str(source_manifest.get("sha256") or "").strip()
        source_manifest_status = str(source_manifest.get("status") or "").strip()
        if not source_manifest_sha256:
            raise MediaPlanError("Serialized media plan is missing source_manifest.sha256.")

    return LockedMediaPlan(
        baseline_path=baseline_path,
        baseline_sha256=baseline_sha256,
        replacements=tuple(replacements),
        source_manifest_path=source_manifest_path,
        source_manifest_sha256=source_manifest_sha256,
        source_manifest_status=source_manifest_status,
    )
