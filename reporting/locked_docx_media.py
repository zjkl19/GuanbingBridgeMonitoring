from __future__ import annotations

import copy
import hashlib
import json
import math
import os
import posixpath
import tempfile
from collections import Counter
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import Any, Mapping
from xml.etree import ElementTree as ET
from zipfile import BadZipFile, ZipFile

from PIL import Image, UnidentifiedImageError


REL_NS = "http://schemas.openxmlformats.org/package/2006/relationships"
OFFICE_REL_NS = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
DRAWING_NS = "http://schemas.openxmlformats.org/drawingml/2006/main"
WORDPROCESSING_DRAWING_NS = "http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"
VML_NS = "urn:schemas-microsoft-com:vml"

IMAGE_DIMENSION_POLICY_EXACT = "exact"
IMAGE_DIMENSION_POLICY_SAME_ASPECT_OR_LARGER = "same_aspect_or_larger"
IMAGE_DIMENSION_POLICIES = frozenset(
    {
        IMAGE_DIMENSION_POLICY_EXACT,
        IMAGE_DIMENSION_POLICY_SAME_ASPECT_OR_LARGER,
    }
)
DEFAULT_MAX_ASPECT_RATIO_ERROR = 0.001


class LockedDocxMediaError(RuntimeError):
    """Base error for strict DOCX media replacement."""


class BaselineMismatchError(LockedDocxMediaError):
    """The baseline DOCX no longer matches the compiled plan."""


class MediaMemberError(LockedDocxMediaError):
    """A requested baseline media member is missing or changed."""


class MediaCandidateError(LockedDocxMediaError):
    """A candidate image is missing, changed, or incompatible."""


class SharedMediaReferenceError(LockedDocxMediaError):
    """A media member is referenced more than once (or not at all)."""


class OutputExistsError(LockedDocxMediaError):
    """The requested output would overwrite an existing file."""


class IntegrityError(LockedDocxMediaError):
    """The patched package changed content outside approved media members."""


@dataclass(frozen=True)
class ImageInfo:
    format: str
    width_px: int
    height_px: int


@dataclass(frozen=True)
class MediaReference:
    relationship_part: str
    source_part: str
    relationship_id: str
    usage_count: int
    extents_emu: tuple[tuple[int, int], ...]


@dataclass(frozen=True)
class MediaMember:
    member: str
    sha256: str
    size_bytes: int
    image_info: ImageInfo | None
    references: tuple[MediaReference, ...]

    @property
    def reference_count(self) -> int:
        return sum(reference.usage_count for reference in self.references)

    @property
    def extents_emu(self) -> tuple[tuple[int, int], ...]:
        return tuple(extent for reference in self.references for extent in reference.extents_emu)


@dataclass(frozen=True)
class DocxInventory:
    path: Path
    sha256: str
    member_order: tuple[str, ...]
    media: dict[str, MediaMember]


@dataclass(frozen=True)
class MediaReplacement:
    slot_id: str
    member: str
    candidate_path: Path
    original_sha256: str
    candidate_sha256: str
    format: str
    width_px: int
    height_px: int
    extents_emu: tuple[tuple[int, int], ...]
    candidate_width_px: int = 0
    candidate_height_px: int = 0
    dimension_policy: str = IMAGE_DIMENSION_POLICY_EXACT
    max_aspect_ratio_error: float = DEFAULT_MAX_ASPECT_RATIO_ERROR
    provenance_path: Path | None = None
    provenance_sha256: str = ""
    provenance_series_count: int = 0
    manifest_artifact_record: str = ""


@dataclass(frozen=True)
class LockedMediaPlan:
    baseline_path: Path
    baseline_sha256: str
    replacements: tuple[MediaReplacement, ...]
    source_manifest_path: Path | None = None
    source_manifest_sha256: str = ""
    source_manifest_status: str = ""


@dataclass(frozen=True)
class ValidationReport:
    ok: bool
    baseline_sha256: str
    replacement_count: int
    members: tuple[str, ...]


@dataclass(frozen=True)
class IntegrityReport:
    ok: bool
    baseline_sha256: str
    output_sha256: str
    member_count: int
    allowed_members: tuple[str, ...]
    changed_members: tuple[str, ...]
    non_allowed_changed: tuple[str, ...]


@dataclass(frozen=True)
class PatchAudit:
    output_path: Path
    baseline_sha256: str
    output_sha256: str
    replaced_members: tuple[str, ...]
    changed_members: tuple[str, ...]
    member_count: int


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path | str) -> str:
    digest = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def read_image_info(path: Path | str) -> ImageInfo:
    image_path = Path(path)
    try:
        with Image.open(image_path) as image:
            image.load()
            image_format = str(image.format or "").upper()
            if not image_format:
                raise MediaCandidateError(f"Unable to identify candidate image format: {image_path}")
            return ImageInfo(image_format, int(image.width), int(image.height))
    except (OSError, UnidentifiedImageError) as exc:
        raise MediaCandidateError(f"Unable to read candidate image: {image_path}: {exc}") from exc


def validate_image_compatibility(
    baseline_info: ImageInfo,
    candidate_info: ImageInfo,
    *,
    dimension_policy: str = IMAGE_DIMENSION_POLICY_EXACT,
    max_aspect_ratio_error: float = DEFAULT_MAX_ASPECT_RATIO_ERROR,
    candidate_label: str = "candidate image",
) -> None:
    """Validate a raster replacement without relying on Word-side recompression.

    The default remains exact pixel equality. The opt-in
    ``same_aspect_or_larger`` policy is intended for a higher-resolution source
    image placed into an already fixed OOXML drawing extent. It never permits a
    lower-resolution replacement or a format change.
    """

    policy = str(dimension_policy or "").strip().lower()
    if policy not in IMAGE_DIMENSION_POLICIES:
        raise MediaCandidateError(
            f"Unsupported image dimension policy for {candidate_label}: {policy or '<missing>'}"
        )
    if isinstance(max_aspect_ratio_error, bool):
        raise MediaCandidateError(
            f"Invalid aspect-ratio tolerance for {candidate_label}: boolean values are not allowed."
        )
    try:
        tolerance = float(max_aspect_ratio_error)
    except (TypeError, ValueError) as exc:
        raise MediaCandidateError(
            f"Invalid aspect-ratio tolerance for {candidate_label}: {max_aspect_ratio_error}"
        ) from exc
    if not math.isfinite(tolerance) or tolerance < 0 or tolerance > 0.01:
        raise MediaCandidateError(
            f"Aspect-ratio tolerance for {candidate_label} must be between 0 and 0.01; got {tolerance}."
        )

    if candidate_info.format.upper() != baseline_info.format.upper():
        raise MediaCandidateError(
            f"Candidate format mismatch for {candidate_label}: "
            f"expected {baseline_info.format}, got {candidate_info.format}"
        )
    if policy == IMAGE_DIMENSION_POLICY_EXACT:
        if candidate_info != baseline_info:
            raise MediaCandidateError(
                f"Candidate dimensions/format mismatch for {candidate_label}: "
                f"expected {baseline_info}, got {candidate_info}"
            )
        return

    if (
        baseline_info.width_px <= 0
        or baseline_info.height_px <= 0
        or candidate_info.width_px <= 0
        or candidate_info.height_px <= 0
    ):
        raise MediaCandidateError(f"Image dimensions must be positive for {candidate_label}.")
    if (
        candidate_info.width_px < baseline_info.width_px
        or candidate_info.height_px < baseline_info.height_px
    ):
        raise MediaCandidateError(
            f"Candidate must not reduce pixel dimensions for {candidate_label}: "
            f"baseline={baseline_info.width_px}x{baseline_info.height_px}, "
            f"candidate={candidate_info.width_px}x{candidate_info.height_px}"
        )

    baseline_ratio = baseline_info.width_px / baseline_info.height_px
    candidate_ratio = candidate_info.width_px / candidate_info.height_px
    relative_error = abs(candidate_ratio - baseline_ratio) / baseline_ratio
    if relative_error > tolerance:
        raise MediaCandidateError(
            f"Candidate aspect ratio differs for {candidate_label}: "
            f"relative_error={relative_error:.8f}, allowed={tolerance:.8f}, "
            f"baseline={baseline_info.width_px}x{baseline_info.height_px}, "
            f"candidate={candidate_info.width_px}x{candidate_info.height_px}"
        )


def normalize_artifact_path(path: Path | str) -> str:
    """Normalize an explicit artifact path for exact manifest membership checks."""

    resolved = Path(path).expanduser().resolve(strict=False)
    return os.path.normcase(os.path.normpath(str(resolved)))


def expected_plot_provenance_path(candidate_path: Path | str) -> Path:
    return Path(candidate_path).expanduser().resolve(strict=False).with_suffix(".plot.json")


def validate_full_plot_provenance(
    provenance_path: Path | str,
    candidate_path: Path | str,
) -> int:
    candidate = Path(candidate_path).expanduser().resolve(strict=False)
    provenance = Path(provenance_path).expanduser().resolve(strict=False)
    expected_path = expected_plot_provenance_path(candidate)
    if normalize_artifact_path(provenance) != normalize_artifact_path(expected_path):
        raise MediaCandidateError(
            f"Plot provenance must use the candidate basename: expected {expected_path}, got {provenance}"
        )
    if not provenance.exists() or not provenance.is_file():
        raise MediaCandidateError(f"Required plot provenance does not exist: {provenance}")
    try:
        payload = json.loads(provenance.read_text(encoding="utf-8-sig"))
    except (OSError, json.JSONDecodeError) as exc:
        raise MediaCandidateError(f"Unable to load plot provenance: {provenance}: {exc}") from exc
    if not isinstance(payload, dict):
        raise MediaCandidateError(f"Plot provenance must be a JSON object: {provenance}")
    file_stub = str(payload.get("file_stub") or "").strip()
    if file_stub != candidate.stem:
        raise MediaCandidateError(
            f"Plot provenance file_stub does not match candidate basename: "
            f"expected {candidate.stem}, got {file_stub or '<missing>'}"
        )

    raw_series = payload.get("series")
    if isinstance(raw_series, dict):
        series = [raw_series]
    elif isinstance(raw_series, list):
        series = raw_series
    else:
        series = []
    if not series or not all(isinstance(item, dict) for item in series):
        raise MediaCandidateError(f"Plot provenance requires at least one series object: {provenance}")

    for index, item in enumerate(series, start=1):
        sampling_mode = str(item.get("sampling_mode") or "").strip().lower()
        if sampling_mode != "full":
            raise MediaCandidateError(
                f"Plot provenance series {index} is not full sampling: {sampling_mode or '<missing>'}"
            )
        if item.get("reduction_applied") is not False:
            raise MediaCandidateError(
                f"Plot provenance series {index} reports reduction_applied != false."
            )
        finite_count = item.get("finite_count")
        plotted_finite_count = item.get("plotted_finite_count")
        valid_numbers = (
            isinstance(finite_count, (int, float))
            and not isinstance(finite_count, bool)
            and isinstance(plotted_finite_count, (int, float))
            and not isinstance(plotted_finite_count, bool)
            and math.isfinite(float(finite_count))
            and math.isfinite(float(plotted_finite_count))
            and float(finite_count) >= 0
            and float(plotted_finite_count) >= 0
        )
        if not valid_numbers:
            raise MediaCandidateError(
                f"Plot provenance series {index} has invalid finite point counts."
            )
        if float(finite_count) != float(plotted_finite_count):
            raise MediaCandidateError(
                f"Plot provenance series {index} point counts differ: "
                f"finite_count={finite_count}, plotted_finite_count={plotted_finite_count}"
            )
    return len(series)


def manifest_artifact_record_for_paths(
    manifest: Mapping[str, Any],
    candidate_path: Path | str,
    provenance_path: Path | str,
) -> str:
    """Require candidate and provenance in the same explicit manifest record."""

    candidate_norm = normalize_artifact_path(candidate_path)
    provenance_norm = normalize_artifact_path(provenance_path)
    candidate_records: set[str] = set()
    provenance_records: set[str] = set()
    for container_name in ("module_results", "module_logs", "module_artifacts"):
        records = manifest.get(container_name) or []
        if isinstance(records, dict):
            records = [records]
        if not isinstance(records, list):
            continue
        for index, record in enumerate(records):
            if not isinstance(record, dict):
                continue
            artifacts = record.get("artifacts") or []
            if isinstance(artifacts, dict):
                artifacts = [artifacts]
            if not isinstance(artifacts, list):
                continue
            artifact_paths: set[str] = set()
            for artifact in artifacts:
                if not isinstance(artifact, dict):
                    continue
                artifact_path = str(artifact.get("path") or "").strip()
                if artifact_path:
                    artifact_paths.add(normalize_artifact_path(artifact_path))
            record_key = str(record.get("key") or record.get("module") or index)
            record_id = f"{container_name}:{record_key}:{index}"
            if candidate_norm in artifact_paths:
                candidate_records.add(record_id)
            if provenance_norm in artifact_paths:
                provenance_records.add(record_id)

    if not candidate_records:
        raise MediaCandidateError(
            f"Candidate image is not an artifact of the explicit analysis manifest: {candidate_path}"
        )
    if not provenance_records:
        raise MediaCandidateError(
            f"Plot provenance is not an artifact of the explicit analysis manifest: {provenance_path}"
        )
    shared_records = sorted(candidate_records & provenance_records)
    if not shared_records:
        raise MediaCandidateError(
            "Candidate image and plot provenance do not belong to the same manifest artifact record."
        )
    return shared_records[0]


def _read_image_info_bytes(data: bytes, member: str) -> ImageInfo | None:
    from io import BytesIO

    try:
        with Image.open(BytesIO(data)) as image:
            image.load()
            image_format = str(image.format or "").upper()
            if not image_format:
                return None
            return ImageInfo(image_format, int(image.width), int(image.height))
    except (OSError, UnidentifiedImageError):
        # Some legacy DOCX media (for example EMF/WMF) is not decodable in all
        # Pillow builds. Such members remain inventory-visible but cannot be a
        # strict raster replacement target.
        return None


def _source_part_for_relationships(relationship_part: str) -> str:
    rel_path = PurePosixPath(relationship_part)
    if rel_path.parent.name != "_rels" or not rel_path.name.endswith(".rels"):
        return ""
    source_name = rel_path.name[: -len(".rels")]
    return str(rel_path.parent.parent / source_name)


def _relationship_attribute_usage(source_root: ET.Element) -> Counter[str]:
    counts: Counter[str] = Counter()
    prefix = f"{{{OFFICE_REL_NS}}}"
    for element in source_root.iter():
        for attribute_name, value in element.attrib.items():
            if attribute_name.startswith(prefix):
                counts[str(value)] += 1
    return counts


def _drawing_extents_by_relationship(source_root: ET.Element) -> dict[str, list[tuple[int, int]]]:
    extents: dict[str, list[tuple[int, int]]] = {}
    containers = [
        *source_root.findall(f".//{{{WORDPROCESSING_DRAWING_NS}}}inline"),
        *source_root.findall(f".//{{{WORDPROCESSING_DRAWING_NS}}}anchor"),
    ]
    for container in containers:
        extent = container.find(f".//{{{WORDPROCESSING_DRAWING_NS}}}extent")
        extent_value: tuple[int, int] | None = None
        if extent is not None:
            try:
                extent_value = (int(extent.attrib["cx"]), int(extent.attrib["cy"]))
            except (KeyError, TypeError, ValueError):
                extent_value = None
        for blip in container.findall(f".//{{{DRAWING_NS}}}blip"):
            relationship_id = blip.attrib.get(f"{{{OFFICE_REL_NS}}}embed")
            if relationship_id and extent_value is not None:
                extents.setdefault(relationship_id, []).append(extent_value)

    # VML pictures do not use wp:extent, but recording the relationship usage
    # still lets strict mode reject shared or orphaned targets.
    for image_data in source_root.findall(f".//{{{VML_NS}}}imagedata"):
        relationship_id = image_data.attrib.get(f"{{{OFFICE_REL_NS}}}id")
        if relationship_id:
            extents.setdefault(relationship_id, [])
    return extents


def _media_references(zf: ZipFile, media_members: set[str]) -> dict[str, list[MediaReference]]:
    references: dict[str, list[MediaReference]] = {member: [] for member in media_members}
    relationship_parts = [
        name
        for name in zf.namelist()
        if name.startswith("word/") and "/_rels/" in name and name.endswith(".rels")
    ]
    for relationship_part in relationship_parts:
        source_part = _source_part_for_relationships(relationship_part)
        if not source_part or source_part not in zf.namelist():
            continue
        try:
            relationship_root = ET.fromstring(zf.read(relationship_part))
            source_root = ET.fromstring(zf.read(source_part))
        except ET.ParseError as exc:
            raise LockedDocxMediaError(f"Invalid OOXML part in {zf.filename}: {exc}") from exc

        usage = _relationship_attribute_usage(source_root)
        extents = _drawing_extents_by_relationship(source_root)
        source_dir = posixpath.dirname(source_part)
        for relationship in relationship_root.findall(f"{{{REL_NS}}}Relationship"):
            rel_type = str(relationship.attrib.get("Type") or "")
            if not rel_type.endswith("/image") or relationship.attrib.get("TargetMode") == "External":
                continue
            relationship_id = str(relationship.attrib.get("Id") or "")
            target = str(relationship.attrib.get("Target") or "")
            resolved_target = posixpath.normpath(posixpath.join(source_dir, target))
            if resolved_target not in references:
                continue
            count = int(usage.get(relationship_id, 0))
            if count <= 0:
                continue
            references[resolved_target].append(
                MediaReference(
                    relationship_part=relationship_part,
                    source_part=source_part,
                    relationship_id=relationship_id,
                    usage_count=count,
                    extents_emu=tuple(extents.get(relationship_id, [])),
                )
            )
    return references


def inventory_docx(path: Path | str) -> DocxInventory:
    docx_path = Path(path).expanduser().resolve()
    if not docx_path.exists() or not docx_path.is_file():
        raise LockedDocxMediaError(f"Baseline DOCX does not exist: {docx_path}")
    try:
        with ZipFile(docx_path) as zf:
            member_order = tuple(zf.namelist())
            duplicates = [name for name, count in Counter(member_order).items() if count > 1]
            if duplicates:
                raise LockedDocxMediaError(
                    f"DOCX contains duplicate ZIP members: {', '.join(sorted(duplicates))}"
                )
            media_names = {
                name
                for name in member_order
                if name.startswith("word/media/") and not name.endswith("/")
            }
            references = _media_references(zf, media_names)
            media: dict[str, MediaMember] = {}
            for member in sorted(media_names):
                data = zf.read(member)
                media[member] = MediaMember(
                    member=member,
                    sha256=sha256_bytes(data),
                    size_bytes=len(data),
                    image_info=_read_image_info_bytes(data, member),
                    references=tuple(references.get(member, [])),
                )
    except BadZipFile as exc:
        raise LockedDocxMediaError(f"Invalid DOCX ZIP package: {docx_path}: {exc}") from exc
    return DocxInventory(
        path=docx_path,
        sha256=sha256_file(docx_path),
        member_order=member_order,
        media=media,
    )


def validate_media_plan(plan: LockedMediaPlan) -> ValidationReport:
    inventory = inventory_docx(plan.baseline_path)
    if inventory.sha256.lower() != plan.baseline_sha256.lower():
        raise BaselineMismatchError(
            f"Baseline SHA-256 mismatch: expected {plan.baseline_sha256}, got {inventory.sha256}"
        )

    members = [replacement.member for replacement in plan.replacements]
    if len(members) != len(set(members)):
        raise MediaMemberError("A media member appears more than once in the replacement plan.")
    slot_ids = [replacement.slot_id for replacement in plan.replacements]
    if len(slot_ids) != len(set(slot_ids)):
        raise MediaMemberError("A slot_id appears more than once in the replacement plan.")

    for replacement in plan.replacements:
        member = inventory.media.get(replacement.member)
        if member is None:
            raise MediaMemberError(f"Baseline media member does not exist: {replacement.member}")
        if member.sha256.lower() != replacement.original_sha256.lower():
            raise MediaMemberError(
                f"Baseline media SHA-256 mismatch for {replacement.member}: "
                f"expected {replacement.original_sha256}, got {member.sha256}"
            )
        if member.reference_count != 1:
            raise SharedMediaReferenceError(
                f"Strict replacement requires exactly one OOXML reference for {replacement.member}; "
                f"found {member.reference_count}."
            )
        if member.image_info is None:
            raise MediaMemberError(f"Baseline media is not a Pillow-readable raster image: {replacement.member}")
        expected_info = ImageInfo(replacement.format.upper(), replacement.width_px, replacement.height_px)
        if member.image_info != expected_info:
            raise MediaMemberError(
                f"Baseline media dimensions/format changed for {replacement.member}: "
                f"expected {expected_info}, got {member.image_info}"
            )
        if member.extents_emu != replacement.extents_emu:
            raise MediaMemberError(
                f"Baseline drawing extent changed for {replacement.member}: "
                f"expected {replacement.extents_emu}, got {member.extents_emu}"
            )

        candidate_path = replacement.candidate_path.expanduser().resolve()
        if not candidate_path.exists() or not candidate_path.is_file():
            raise MediaCandidateError(f"Candidate image does not exist: {candidate_path}")
        candidate_sha256 = sha256_file(candidate_path)
        if candidate_sha256.lower() != replacement.candidate_sha256.lower():
            raise MediaCandidateError(
                f"Candidate SHA-256 mismatch for {candidate_path}: "
                f"expected {replacement.candidate_sha256}, got {candidate_sha256}"
            )
        candidate_info = read_image_info(candidate_path)
        if replacement.candidate_width_px <= 0 or replacement.candidate_height_px <= 0:
            raise MediaCandidateError(
                f"Pinned candidate dimensions must be positive for {candidate_path}: "
                f"{replacement.candidate_width_px}x{replacement.candidate_height_px}"
            )
        expected_candidate_info = ImageInfo(
            replacement.format.upper(),
            replacement.candidate_width_px,
            replacement.candidate_height_px,
        )
        if candidate_info != expected_candidate_info:
            raise MediaCandidateError(
                f"Candidate image metadata changed for {candidate_path}: "
                f"expected {expected_candidate_info}, got {candidate_info}"
            )
        validate_image_compatibility(
            expected_info,
            candidate_info,
            dimension_policy=replacement.dimension_policy,
            max_aspect_ratio_error=replacement.max_aspect_ratio_error,
            candidate_label=str(candidate_path),
        )

    if plan.source_manifest_path is not None:
        manifest_path = plan.source_manifest_path.expanduser().resolve()
        if not manifest_path.exists() or not manifest_path.is_file():
            raise MediaCandidateError(f"Explicit source manifest does not exist: {manifest_path}")
        manifest_sha256 = sha256_file(manifest_path)
        if manifest_sha256.lower() != plan.source_manifest_sha256.lower():
            raise MediaCandidateError(
                f"Source manifest SHA-256 mismatch: expected {plan.source_manifest_sha256}, "
                f"got {manifest_sha256}"
            )
        try:
            manifest_payload = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
        except (OSError, json.JSONDecodeError) as exc:
            raise MediaCandidateError(f"Unable to load explicit source manifest: {manifest_path}: {exc}") from exc
        if not isinstance(manifest_payload, dict):
            raise MediaCandidateError(f"Explicit source manifest must be a JSON object: {manifest_path}")
        manifest_status = str(manifest_payload.get("status") or "").strip().lower()
        if manifest_status not in {"ok", "completed", "complete", "success", "succeeded"}:
            raise MediaCandidateError(
                f"Explicit source manifest status is not accepted: {manifest_status or '<missing>'}"
            )
        if plan.source_manifest_status and manifest_status != plan.source_manifest_status.lower():
            raise MediaCandidateError(
                f"Explicit source manifest status changed: expected {plan.source_manifest_status}, "
                f"got {manifest_status}"
            )
        for replacement in plan.replacements:
            if replacement.provenance_path is None or not replacement.provenance_sha256:
                raise MediaCandidateError(
                    f"Manifest-bound replacement lacks plot provenance: {replacement.slot_id}"
                )
            provenance_path = replacement.provenance_path.expanduser().resolve()
            if not provenance_path.exists() or not provenance_path.is_file():
                raise MediaCandidateError(f"Required plot provenance does not exist: {provenance_path}")
            provenance_sha256 = sha256_file(provenance_path)
            if provenance_sha256.lower() != replacement.provenance_sha256.lower():
                raise MediaCandidateError(
                    f"Plot provenance SHA-256 mismatch for {provenance_path}: "
                    f"expected {replacement.provenance_sha256}, got {provenance_sha256}"
                )
            series_count = validate_full_plot_provenance(
                provenance_path, replacement.candidate_path
            )
            if series_count != replacement.provenance_series_count:
                raise MediaCandidateError(
                    f"Plot provenance series count changed for {provenance_path}: "
                    f"expected {replacement.provenance_series_count}, got {series_count}"
                )
            record_id = manifest_artifact_record_for_paths(
                manifest_payload,
                replacement.candidate_path,
                provenance_path,
            )
            if replacement.manifest_artifact_record and (
                record_id != replacement.manifest_artifact_record
            ):
                raise MediaCandidateError(
                    f"Manifest artifact record changed for {replacement.slot_id}: "
                    f"expected {replacement.manifest_artifact_record}, got {record_id}"
                )

    return ValidationReport(
        ok=True,
        baseline_sha256=inventory.sha256,
        replacement_count=len(plan.replacements),
        members=tuple(members),
    )


def verify_media_only_change(
    baseline_docx: Path | str,
    output_docx: Path | str,
    allowed_members: set[str] | frozenset[str],
    *,
    expected_media: Mapping[str, bytes] | None = None,
) -> IntegrityReport:
    baseline_path = Path(baseline_docx)
    output_path = Path(output_docx)
    expected_media = expected_media or {}
    try:
        with ZipFile(baseline_path) as baseline_zip, ZipFile(output_path) as output_zip:
            baseline_order = baseline_zip.namelist()
            output_order = output_zip.namelist()
            if baseline_order != output_order:
                raise IntegrityError("DOCX member names or order changed during strict media replacement.")
            missing_allowed = sorted(set(allowed_members) - set(baseline_order))
            if missing_allowed:
                raise IntegrityError(
                    f"Approved media members are missing from baseline: {', '.join(missing_allowed)}"
                )

            changed: list[str] = []
            non_allowed_changed: list[str] = []
            for member in baseline_order:
                baseline_data = baseline_zip.read(member)
                output_data = output_zip.read(member)
                if baseline_data != output_data:
                    changed.append(member)
                    if member not in allowed_members:
                        non_allowed_changed.append(member)
                if member in expected_media and output_data != expected_media[member]:
                    raise IntegrityError(f"Output media bytes do not match approved candidate: {member}")
            if non_allowed_changed:
                raise IntegrityError(
                    "Strict replacement changed unapproved members: "
                    + ", ".join(non_allowed_changed)
                )
    except BadZipFile as exc:
        raise IntegrityError(f"Patched output is not a valid DOCX ZIP package: {exc}") from exc

    return IntegrityReport(
        ok=True,
        baseline_sha256=sha256_file(baseline_path),
        output_sha256=sha256_file(output_path),
        member_count=len(baseline_order),
        allowed_members=tuple(sorted(allowed_members)),
        changed_members=tuple(changed),
        non_allowed_changed=tuple(non_allowed_changed),
    )


def _write_candidate_docx(
    baseline_path: Path,
    temp_path: Path,
    candidate_bytes: Mapping[str, bytes],
) -> None:
    with ZipFile(baseline_path) as baseline_zip, ZipFile(temp_path, mode="w") as output_zip:
        output_zip.comment = baseline_zip.comment
        for info in baseline_zip.infolist():
            data = candidate_bytes.get(info.filename)
            if data is None:
                data = baseline_zip.read(info.filename)
            output_zip.writestr(copy.copy(info), data)


def apply_media_plan(
    plan: LockedMediaPlan,
    output_docx: Path | str,
    *,
    overwrite: bool = False,
) -> PatchAudit:
    output_path = Path(output_docx).expanduser().resolve()
    baseline_path = plan.baseline_path.expanduser().resolve()
    if output_path == baseline_path:
        raise OutputExistsError("Strict media output must not overwrite the baseline DOCX.")
    if output_path.exists() and not overwrite:
        raise OutputExistsError(f"Output already exists (use overwrite=True explicitly): {output_path}")

    validate_media_plan(plan)
    candidate_bytes: dict[str, bytes] = {}
    for replacement in plan.replacements:
        candidate_path = replacement.candidate_path.expanduser().resolve()
        data = candidate_path.read_bytes()
        actual_sha256 = sha256_bytes(data)
        if actual_sha256.lower() != replacement.candidate_sha256.lower():
            raise MediaCandidateError(
                f"Candidate changed while preparing output for {candidate_path}: "
                f"expected {replacement.candidate_sha256}, got {actual_sha256}"
            )
        image_info = _read_image_info_bytes(data, str(candidate_path))
        expected_candidate_info = ImageInfo(
            replacement.format.upper(),
            replacement.candidate_width_px,
            replacement.candidate_height_px,
        )
        if image_info != expected_candidate_info:
            raise MediaCandidateError(
                f"Candidate image metadata changed while preparing output for {candidate_path}: "
                f"expected {expected_candidate_info}, got {image_info}"
            )
        candidate_bytes[replacement.member] = data
    output_path.parent.mkdir(parents=True, exist_ok=True)
    temp_handle = tempfile.NamedTemporaryFile(
        prefix=f".{output_path.name}.",
        suffix=".tmp",
        dir=output_path.parent,
        delete=False,
    )
    temp_path = Path(temp_handle.name)
    temp_handle.close()
    try:
        _write_candidate_docx(baseline_path, temp_path, candidate_bytes)
        integrity = verify_media_only_change(
            baseline_path,
            temp_path,
            set(candidate_bytes),
            expected_media=candidate_bytes,
        )
        if output_path.exists() and not overwrite:
            raise OutputExistsError(f"Output appeared while patching and was not overwritten: {output_path}")
        os.replace(temp_path, output_path)
        return PatchAudit(
            output_path=output_path,
            baseline_sha256=integrity.baseline_sha256,
            output_sha256=sha256_file(output_path),
            replaced_members=tuple(sorted(candidate_bytes)),
            changed_members=integrity.changed_members,
            member_count=integrity.member_count,
        )
    except Exception:
        try:
            temp_path.unlink(missing_ok=True)
        except OSError:
            pass
        raise


def inventory_to_dict(inventory: DocxInventory) -> dict[str, Any]:
    return {
        "path": str(inventory.path),
        "sha256": inventory.sha256,
        "member_count": len(inventory.member_order),
        "media_count": len(inventory.media),
        "media": [
            {
                "member": member.member,
                "sha256": member.sha256,
                "size_bytes": member.size_bytes,
                "format": member.image_info.format if member.image_info else "",
                "width_px": member.image_info.width_px if member.image_info else None,
                "height_px": member.image_info.height_px if member.image_info else None,
                "reference_count": member.reference_count,
                "extents_emu": [list(extent) for extent in member.extents_emu],
                "references": [
                    {
                        "relationship_part": reference.relationship_part,
                        "source_part": reference.source_part,
                        "relationship_id": reference.relationship_id,
                        "usage_count": reference.usage_count,
                        "extents_emu": [list(extent) for extent in reference.extents_emu],
                    }
                    for reference in member.references
                ],
            }
            for member in inventory.media.values()
        ],
    }


def validation_report_to_dict(report: ValidationReport) -> dict[str, Any]:
    return {
        "ok": report.ok,
        "baseline_sha256": report.baseline_sha256,
        "replacement_count": report.replacement_count,
        "members": list(report.members),
    }


def patch_audit_to_dict(audit: PatchAudit) -> dict[str, Any]:
    return {
        "output_path": str(audit.output_path),
        "baseline_sha256": audit.baseline_sha256,
        "output_sha256": audit.output_sha256,
        "replaced_members": list(audit.replaced_members),
        "changed_members": list(audit.changed_members),
        "member_count": audit.member_count,
    }
