from __future__ import annotations

import hashlib
import json
import re
from contextlib import contextmanager
from contextvars import ContextVar
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterator


@dataclass(frozen=True)
class PinnedAnalysisManifest:
    """One immutable analysis-manifest binding for a strict report build."""

    path: Path
    sha256: str
    payload: dict[str, Any]
    result_root: Path


@dataclass(frozen=True)
class PinnedDerivedArtifactManifest:
    """File-level binding for reviewed artifacts omitted by an analysis manifest.

    This is intentionally separate from :class:`PinnedAnalysisManifest`: a
    derived-artifact sidecar must never masquerade as an analyzer-native
    artifact record.  It is only used to bridge known producer-manifest gaps
    while retaining exact path, size and SHA-256 verification.
    """

    path: Path
    sha256: str
    payload: dict[str, Any]
    result_root: Path


_PINNED_ANALYSIS_MANIFEST: ContextVar[PinnedAnalysisManifest | None] = ContextVar(
    "pinned_analysis_manifest",
    default=None,
)
_PINNED_DERIVED_ARTIFACT_MANIFEST: ContextVar[PinnedDerivedArtifactManifest | None] = ContextVar(
    "pinned_derived_artifact_manifest",
    default=None,
)


def _read_bytes_with_sha256(path: Path) -> tuple[bytes, str]:
    raw = path.read_bytes()
    return raw, hashlib.sha256(raw).hexdigest().upper()


def _read_json_object_with_sha256(path: Path, *, label: str) -> tuple[dict[str, Any], str]:
    raw, sha256 = _read_bytes_with_sha256(path)
    try:
        payload = json.loads(raw.decode("utf-8-sig"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ValueError(f"{label} must contain valid UTF-8 JSON: {path}: {exc}") from exc
    if not isinstance(payload, dict):
        raise ValueError(f"{label} must contain a JSON object: {path}")
    return payload, sha256


def _require_within_root(path: Path, root: Path, *, label: str) -> None:
    try:
        path.relative_to(root)
    except ValueError as exc:
        raise ValueError(f"{label} is outside result_root: {path}") from exc


def active_pinned_analysis_manifest() -> PinnedAnalysisManifest | None:
    return _PINNED_ANALYSIS_MANIFEST.get()


def active_pinned_derived_artifact_manifest() -> PinnedDerivedArtifactManifest | None:
    return _PINNED_DERIVED_ARTIFACT_MANIFEST.get()


@contextmanager
def pinned_analysis_manifest_scope(
    path: Path | str | None,
    expected_sha256: str = "",
    *,
    require_source_provenance: bool = False,
    result_root: Path | str | None = None,
) -> Iterator[PinnedAnalysisManifest | None]:
    """Bind exact analysis artifacts for one strict report execution.

    Legacy/non-strict callers retain latest-manifest and filesystem fallback
    behavior. A strict caller must provide both the exact manifest and its
    reviewed SHA-256; a mismatch fails before any report artifact is read.
    """

    if not require_source_provenance:
        yield active_pinned_analysis_manifest()
        return
    if path is None or not str(path).strip():
        raise ValueError("Strict source provenance requires an analysis manifest path.")
    if result_root is None or not str(result_root).strip():
        raise ValueError("Strict source provenance requires an allowed result_root.")
    allowed_root = Path(result_root).expanduser().resolve()
    if not allowed_root.is_dir():
        raise FileNotFoundError(f"Strict source provenance result_root does not exist: {allowed_root}")
    manifest_path = Path(path).expanduser().resolve()
    _require_within_root(manifest_path, allowed_root, label="Pinned analysis manifest")
    if not manifest_path.is_file():
        raise FileNotFoundError(f"Pinned analysis manifest does not exist: {manifest_path}")
    expected = str(expected_sha256 or "").strip().upper()
    if not expected:
        raise ValueError("Strict source provenance requires an analysis manifest SHA-256.")
    payload, actual = _read_json_object_with_sha256(
        manifest_path, label="Pinned analysis manifest"
    )
    if actual != expected:
        raise ValueError(
            f"Pinned analysis manifest SHA-256 mismatch: expected {expected}, got {actual}: {manifest_path}"
        )
    binding = PinnedAnalysisManifest(manifest_path, actual, payload, allowed_root)
    token = _PINNED_ANALYSIS_MANIFEST.set(binding)
    try:
        yield binding
    finally:
        _PINNED_ANALYSIS_MANIFEST.reset(token)


@contextmanager
def pinned_derived_artifact_manifest_scope(
    path: Path | str | None,
    expected_sha256: str = "",
    *,
    require_source_provenance: bool = False,
) -> Iterator[PinnedDerivedArtifactManifest | None]:
    """Bind a reviewed file-level sidecar to the active analysis manifest.

    The sidecar is optional, even for strict report jobs.  When supplied it
    must identify the active analysis manifest by both path and SHA-256, and
    every artifact entry is re-hashed before the report can use it.
    """

    path_present = path is not None and bool(str(path).strip())
    hash_present = bool(str(expected_sha256 or "").strip())
    if not path_present and not hash_present:
        yield None
        return
    if path_present != hash_present:
        raise ValueError("Derived-artifact manifest path and SHA-256 must be provided together.")
    if not require_source_provenance:
        raise ValueError("A derived-artifact manifest requires strict source provenance.")
    analysis = active_pinned_analysis_manifest()
    if analysis is None:
        raise ValueError("A derived-artifact manifest requires an active pinned analysis manifest.")

    manifest_path = Path(path).expanduser().resolve()
    _require_within_root(
        manifest_path, analysis.result_root, label="Derived-artifact manifest"
    )
    if not manifest_path.is_file():
        raise FileNotFoundError(f"Derived-artifact manifest does not exist: {manifest_path}")
    expected = str(expected_sha256 or "").strip().upper()
    if not expected:
        raise ValueError("A derived-artifact manifest SHA-256 is required.")
    payload, actual = _read_json_object_with_sha256(
        manifest_path, label="Derived-artifact manifest"
    )
    if actual != expected:
        raise ValueError(
            f"Derived-artifact manifest SHA-256 mismatch: expected {expected}, got {actual}: {manifest_path}"
        )
    if str(payload.get("manifest_type") or "") != "derived_artifact_manifest":
        raise ValueError("Derived-artifact manifest_type must be 'derived_artifact_manifest'.")

    parent = payload.get("analysis_manifest")
    if not isinstance(parent, dict):
        raise ValueError("Derived-artifact manifest must identify its analysis_manifest parent.")
    parent_path = Path(str(parent.get("path") or "")).expanduser().resolve()
    parent_sha = str(parent.get("sha256") or "").strip().upper()
    if parent_path != analysis.path or parent_sha != analysis.sha256:
        raise ValueError("Derived-artifact manifest is not bound to the active analysis manifest.")

    result_root_text = str(payload.get("result_root") or "").strip()
    if not result_root_text:
        raise ValueError("Derived-artifact manifest must declare result_root.")
    result_root = Path(result_root_text).expanduser().resolve()
    if result_root != analysis.result_root:
        raise ValueError("Derived-artifact manifest result_root does not match the active report root.")
    artifacts = payload.get("artifacts")
    if not isinstance(artifacts, list) or not artifacts:
        raise ValueError("Derived-artifact manifest must contain a non-empty artifacts list.")
    seen: set[Path] = set()
    for index, record in enumerate(artifacts):
        if not isinstance(record, dict):
            raise ValueError(f"Derived-artifact entry {index} must be an object.")
        artifact_path = Path(str(record.get("path") or "")).expanduser().resolve()
        _require_within_root(
            artifact_path, result_root, label=f"Derived-artifact entry {index}"
        )
        if artifact_path in seen:
            raise ValueError(f"Duplicate derived-artifact path: {artifact_path}")
        seen.add(artifact_path)
        if not artifact_path.is_file():
            raise FileNotFoundError(f"Derived artifact does not exist: {artifact_path}")
        expected_artifact_sha = str(record.get("sha256") or "").strip().upper()
        if not expected_artifact_sha:
            raise ValueError(f"Derived artifact is missing SHA-256: {artifact_path}")
        raw_artifact, actual_artifact_sha = _read_bytes_with_sha256(artifact_path)
        if actual_artifact_sha != expected_artifact_sha:
            raise ValueError(
                f"Derived artifact SHA-256 mismatch: expected {expected_artifact_sha}, "
                f"got {actual_artifact_sha}: {artifact_path}"
            )
        expected_bytes = record.get("bytes")
        if expected_bytes is not None and int(expected_bytes) != len(raw_artifact):
            raise ValueError(f"Derived artifact size mismatch: {artifact_path}")

    binding = PinnedDerivedArtifactManifest(manifest_path, actual, payload, result_root)
    token = _PINNED_DERIVED_ARTIFACT_MANIFEST.set(binding)
    try:
        yield binding
    finally:
        _PINNED_DERIVED_ARTIFACT_MANIFEST.reset(token)


def find_latest_analysis_manifest(result_root: Path | str | None) -> Path | None:
    """Return the newest MATLAB analysis manifest under result_root/run_logs."""
    if result_root is None:
        return None
    root = Path(result_root)
    candidates: list[Path] = []
    search_roots = [root / "run_logs", root]
    for folder in search_roots:
        if not folder.exists() or not folder.is_dir():
            continue
        candidates.extend(folder.glob("analysis_manifest_*.json"))
    if not candidates:
        return None
    return max(candidates, key=lambda p: p.stat().st_mtime)


def load_analysis_manifest(path: Path | str | None) -> dict[str, Any] | None:
    if path is None:
        return None
    p = Path(path)
    if not p.exists():
        return None
    payload, _sha256_value = _read_json_object_with_sha256(p, label="Analysis manifest")
    return payload


def _successful_module_keys(manifest: dict[str, Any]) -> set[str]:
    keys: set[str] = set()
    for field in ("module_results", "module_logs"):
        for item in manifest.get(field, []) or []:
            if not isinstance(item, dict):
                continue
            if str(item.get("status") or "").lower() != "ok":
                continue
            key = str(item.get("key") or item.get("module") or "")
            if key:
                keys.add(key)
    return keys


def load_latest_analysis_manifest(result_root: Path | str | None) -> tuple[Path | None, dict[str, Any] | None]:
    pinned = active_pinned_analysis_manifest()
    if pinned is not None:
        return pinned.path, pinned.payload
    path = find_latest_analysis_manifest(result_root)
    return path, load_analysis_manifest(path)


def _module_label(item: dict[str, Any]) -> str:
    return str(item.get("label") or item.get("key") or item.get("module") or "unknown")


def manifest_missing_modules(manifest: dict[str, Any] | None) -> list[dict[str, str]]:
    """Normalize missing/failed module information from the MATLAB run manifest."""
    if not isinstance(manifest, dict):
        return []

    missing: list[dict[str, str]] = []
    seen: set[tuple[str, str]] = set()
    successful_keys = _successful_module_keys(manifest)

    for item in manifest.get("module_preflight", []) or []:
        if not isinstance(item, dict):
            continue
        status = str(item.get("status") or "").lower()
        exists = item.get("exists")
        if status == "missing" or exists is False:
            key = str(item.get("key") or _module_label(item))
            if key in successful_keys:
                continue
            rec = {
                "key": key,
                "label": _module_label(item),
                "status": "missing",
                "message": str(item.get("message") or "stats file missing"),
                "stats_path": str(item.get("stats_path") or ""),
            }
            marker = (rec["key"], rec["status"])
            if marker not in seen:
                seen.add(marker)
                missing.append(rec)

    module_records = manifest.get("module_results") or manifest.get("module_logs") or []
    for item in module_records:
        if not isinstance(item, dict):
            continue
        status = str(item.get("status") or "").lower()
        if status in {"fail", "failed", "skip", "missing"}:
            key = str(item.get("key") or _module_label(item))
            rec = {
                "key": key,
                "label": _module_label(item),
                "status": status,
                "message": str(item.get("message") or ""),
                "error_type": str(item.get("error_type") or ""),
                "stats_path": str(item.get("stats_path") or ""),
            }
            marker = (rec["key"], rec["status"])
            if marker not in seen:
                seen.add(marker)
                missing.append(rec)

    return missing


def analysis_manifest_context(result_root: Path | str | None) -> dict[str, Any]:
    path, manifest = load_latest_analysis_manifest(result_root)
    pinned = active_pinned_analysis_manifest()
    derived = active_pinned_derived_artifact_manifest()
    return {
        "path": str(path) if path is not None else "",
        "sha256": pinned.sha256 if pinned is not None else "",
        "strict_source_provenance": pinned is not None,
        "available": manifest is not None,
        "schema_version": manifest.get("schema_version") if isinstance(manifest, dict) else None,
        "status": manifest.get("status") if isinstance(manifest, dict) else "",
        "bridge_profile": manifest.get("bridge_profile", {}) if isinstance(manifest, dict) else {},
        "data_layout": manifest.get("data_layout", {}) if isinstance(manifest, dict) else {},
        "run_request": manifest.get("run_request", {}) if isinstance(manifest, dict) else {},
        "run_preflight": manifest.get("run_preflight", {}) if isinstance(manifest, dict) else {},
        "missing_modules": manifest_missing_modules(manifest),
        "module_artifacts": manifest.get("module_artifacts", []) if isinstance(manifest, dict) else [],
        "artifact_count": manifest.get("artifact_count", 0) if isinstance(manifest, dict) else 0,
        "derived_artifact_manifest": {
            "available": derived is not None,
            "path": str(derived.path) if derived is not None else "",
            "sha256": derived.sha256 if derived is not None else "",
            "artifact_count": len(derived.payload.get("artifacts") or []) if derived is not None else 0,
        },
        "manifest": manifest,
    }


def manifest_module_records(manifest: dict[str, Any] | None) -> list[dict[str, Any]]:
    if not isinstance(manifest, dict):
        return []
    records = manifest.get("module_results") or manifest.get("module_logs") or []
    return [item for item in records if isinstance(item, dict)]


def _manifest_artifact_records(
    manifest: dict[str, Any] | None,
    key: str,
    *,
    kind: str | None = None,
    role: str | None = None,
    suffixes: tuple[str, ...] | None = None,
) -> list[tuple[Path, dict[str, Any]]]:
    out: list[tuple[Path, dict[str, Any]]] = []
    key = str(key)
    suffixes_lc = tuple(s.lower() for s in suffixes) if suffixes else None
    strict = active_pinned_analysis_manifest()
    for item in manifest_module_records(manifest):
        if str(item.get("key") or "") != key:
            continue
        for artifact in item.get("artifacts") or []:
            if not isinstance(artifact, dict):
                continue
            if kind and str(artifact.get("kind") or "") != kind:
                continue
            artifact_role = str(artifact.get("role") or "")
            if role and artifact_role and artifact_role != role:
                continue
            path = Path(str(artifact.get("path") or "")).expanduser().resolve()
            if strict is not None:
                _require_within_root(path, strict.result_root, label="Pinned analysis artifact")
            elif not path.exists():
                continue
            if suffixes_lc and path.suffix.lower() not in suffixes_lc:
                continue
            out.append((path, artifact))
    return out


def _verify_pinned_analysis_artifact(
    path: Path, record: dict[str, Any]
) -> Path:
    binding = active_pinned_analysis_manifest()
    if binding is None:
        if not path.is_file():
            raise FileNotFoundError(f"Analysis artifact does not exist: {path}")
        return path
    _require_within_root(path, binding.result_root, label="Pinned analysis artifact")
    if record.get("exists") is False:
        raise FileNotFoundError(f"Pinned analysis manifest marks artifact missing: {path}")
    if not path.is_file():
        raise FileNotFoundError(f"Pinned analysis artifact does not exist: {path}")
    expected_bytes = record.get("bytes")
    if expected_bytes is None:
        raise ValueError(f"Pinned analysis artifact is missing its byte count: {path}")
    expected_sha = str(record.get("sha256") or "").strip().upper()
    if not expected_sha:
        raise ValueError(f"Pinned analysis artifact is missing its SHA-256: {path}")
    actual_bytes = path.stat().st_size
    if int(expected_bytes) != actual_bytes:
        raise ValueError(
            f"Pinned analysis artifact size mismatch: expected {expected_bytes}, "
            f"got {actual_bytes}: {path}"
        )
    raw, actual_sha = _read_bytes_with_sha256(path)
    if len(raw) != actual_bytes:
        raise ValueError(f"Pinned analysis artifact changed while being read: {path}")
    if actual_sha != expected_sha:
        raise ValueError(
            f"Pinned analysis artifact SHA-256 mismatch: expected {expected_sha}, "
            f"got {actual_sha}: {path}"
        )
    return path


def _verify_derived_artifact_record(record: dict[str, Any]) -> Path:
    binding = active_pinned_derived_artifact_manifest()
    if binding is None:
        raise ValueError("No derived-artifact manifest is active.")
    path = Path(str(record.get("path") or "")).expanduser().resolve()
    _require_within_root(path, binding.result_root, label="Derived artifact")
    if not path.is_file():
        raise FileNotFoundError(f"Derived artifact does not exist: {path}")
    expected_sha = str(record.get("sha256") or "").strip().upper()
    expected_bytes = record.get("bytes")
    if not expected_sha or expected_bytes is None:
        raise ValueError(f"Derived artifact requires bytes and SHA-256: {path}")
    raw, actual_sha = _read_bytes_with_sha256(path)
    if len(raw) != int(expected_bytes):
        raise ValueError(f"Derived artifact size mismatch: {path}")
    if actual_sha != expected_sha:
        raise ValueError(
            f"Derived artifact SHA-256 mismatch: expected {expected_sha}, "
            f"got {actual_sha}: {path}"
        )
    return path


def derived_manifest_artifact_record(
    *, kind: str | None = None, role: str | None = None, module: str | None = None
) -> dict[str, Any] | None:
    """Return one exact, revalidated record from the active derived sidecar."""

    binding = active_pinned_derived_artifact_manifest()
    if binding is None:
        return None
    matches: list[dict[str, Any]] = []
    for record in binding.payload.get("artifacts") or []:
        if not isinstance(record, dict):
            continue
        if kind and str(record.get("kind") or "") != kind:
            continue
        if role and str(record.get("role") or "") != role:
            continue
        if module and str(record.get("module") or "") != module:
            continue
        matches.append(record)
    if not matches:
        return None
    if len(matches) != 1:
        raise ValueError(
            f"Derived-artifact lookup is ambiguous for kind={kind!r}, "
            f"role={role!r}, module={module!r}."
        )
    _verify_derived_artifact_record(matches[0])
    return dict(matches[0])


def read_verified_derived_artifact_bytes(
    *, kind: str | None = None, role: str | None = None, module: str | None = None
) -> tuple[Path, bytes, dict[str, Any]] | None:
    """Read one sidecar-bound artifact once and verify that exact byte stream."""

    record = derived_manifest_artifact_record(kind=kind, role=role, module=module)
    if record is None:
        return None
    binding = active_pinned_derived_artifact_manifest()
    if binding is None:  # defensive; record lookup above requires it
        raise ValueError("No derived-artifact manifest is active.")
    path = Path(str(record.get("path") or "")).expanduser().resolve()
    _require_within_root(path, binding.result_root, label="Derived artifact")
    raw, actual_sha = _read_bytes_with_sha256(path)
    expected_sha = str(record.get("sha256") or "").strip().upper()
    expected_bytes = int(record.get("bytes"))
    if len(raw) != expected_bytes or actual_sha != expected_sha:
        raise ValueError(f"Derived artifact changed while being read: {path}")
    return path, raw, record


def manifest_stats_path(manifest: dict[str, Any] | None, key: str, filename: str | None = None) -> Path | None:
    """Return a stats path from manifest v1/v2 module records when available."""
    key = str(key)
    filename = str(filename) if filename else None
    for item in manifest_module_records(manifest):
        if str(item.get("key") or "") != key:
            continue
        strict = active_pinned_analysis_manifest()
        if strict is not None:
            for path, artifact in _manifest_artifact_records(
                {"module_results": [item]}, key, kind="stats"
            ):
                if filename is None or path.name == filename:
                    return _verify_pinned_analysis_artifact(path, artifact)
            return None
        stats_path = str(item.get("stats_path") or "")
        if stats_path:
            path = Path(stats_path)
            if path.exists() and (filename is None or path.name == filename):
                return path
        for artifact in item.get("artifacts") or []:
            if not isinstance(artifact, dict):
                continue
            if artifact.get("kind") != "stats":
                continue
            path = Path(str(artifact.get("path") or ""))
            if path.exists() and (filename is None or path.name == filename):
                return path
    return None


def manifest_artifact_paths(
    manifest: dict[str, Any] | None,
    key: str,
    *,
    kind: str | None = None,
    role: str | None = None,
    suffixes: tuple[str, ...] | None = None,
) -> list[Path]:
    """Return artifact paths for a module from manifest schema v2."""
    records = _manifest_artifact_records(
        manifest, key, kind=kind, role=role, suffixes=suffixes
    )
    if active_pinned_analysis_manifest() is not None:
        return [
            _verify_pinned_analysis_artifact(path, record)
            for path, record in records
        ]
    return [path for path, _record in records if path.exists()]


_DIR_KEY_HINTS: tuple[tuple[str, str], ...] = (
    ("动应变箱线图_高通", "dynamic_strain_highpass"),
    ("时程曲线_动应变_高通", "dynamic_strain_highpass"),
    ("动应变箱线图_低通", "dynamic_strain_lowpass"),
    ("时程曲线_动应变_低通", "dynamic_strain_lowpass"),
    ("频谱峰值曲线_索力加速度", "cable_accel_spectrum"),
    ("索力加速度", "cable_accel"),
    ("索力时程", "cable_accel_spectrum"),
    ("索力", "cable_accel_spectrum"),
    ("频谱峰值曲线_加速度", "accel_spectrum"),
    ("加速度_RMS", "acceleration"),
    ("加速度", "acceleration"),
    ("风速风向", "wind"),
    ("风玫瑰", "wind"),
    ("风速10min", "wind"),
    ("地震动", "earthquake"),
    ("支座", "bearing_displacement"),
    ("倾斜", "tilt"),
    ("倾角", "tilt"),
    ("挠度", "deflection"),
    ("裂缝", "crack"),
    ("应变", "strain"),
    ("温度", "temperature"),
    ("湿度", "humidity"),
    ("雨量", "rainfall"),
    ("GNSS", "gnss"),
    ("gnss", "gnss"),
    ("WIM", "wim"),
)


def derived_manifest_latest_artifact(
    root: Path | str,
    *,
    token: str | None = None,
    kind: str | None = "figure",
    role: str | None = None,
    suffixes: tuple[str, ...] | None = (".jpg", ".jpeg", ".png"),
    directory_hint: str | Path | None = None,
    strict_point_token: bool = False,
) -> Path | None:
    """Return a matching artifact from the active reviewed sidecar only."""

    binding = active_pinned_derived_artifact_manifest()
    if binding is None:
        return None
    root_path = Path(root).expanduser().resolve()
    suffixes_lc = tuple(item.lower() for item in suffixes) if suffixes else None
    token_text = str(token or "").strip()
    hint_text = str(directory_hint or "").replace("\\", "/").strip("/")
    matches: list[tuple[Path, dict[str, Any]]] = []
    for record in binding.payload.get("artifacts") or []:
        if not isinstance(record, dict):
            continue
        if kind and str(record.get("kind") or "") != kind:
            continue
        artifact_role = str(record.get("role") or "")
        if role and artifact_role and artifact_role != role:
            continue
        path = Path(str(record.get("path") or "")).expanduser().resolve()
        try:
            path.relative_to(root_path)
        except ValueError:
            continue
        if suffixes_lc and path.suffix.lower() not in suffixes_lc:
            continue
        if token_text:
            if strict_point_token:
                token_pattern = re.escape(token_text)
                if re.search(rf"(?<![A-Za-z0-9]){token_pattern}(?![A-Za-z0-9])", path.stem) is None:
                    continue
            elif token_text not in path.stem:
                continue
        if hint_text:
            parent_text = str(path.parent).replace("\\", "/").rstrip("/")
            if not (parent_text.endswith("/" + hint_text) or parent_text.endswith(hint_text)):
                continue
        matches.append((path, record))
    if not matches:
        return None
    _selected_path, selected_record = max(
        matches, key=lambda item: item[0].stat().st_mtime
    )
    return _verify_derived_artifact_record(selected_record)


def manifest_key_for_dir(configured_dir: str | Path | None) -> str | None:
    text = str(configured_dir or "")
    text_norm = text.replace("\\", "/")
    for token, key in _DIR_KEY_HINTS:
        if token in text_norm:
            return key
    return None


def manifest_role_for_lookup(configured_dir: str | Path | None, token: str | None = None) -> str | None:
    text = f"{configured_dir or ''}/{token or ''}".replace("\\", "/").lower()
    if "rms10" in text:
        return "rms10min"
    if "specfreq" in text or "psd" in text or "频谱" in text:
        return "spectrum"
    if "boxplot" in text or "箱线" in text:
        return "boxplot"
    if "windrose" in text or "风玫瑰" in text:
        return "wind_rose"
    if "freq" in text or "频率" in text or "频次" in text:
        return "frequency_distribution"
    if "speed10min" in text or "风速10min" in text:
        return "wind_speed10min"
    if "filt" in text or "滤波" in text:
        return "filtered"
    if "orig" in text or "原始" in text:
        return "raw"
    return None


def manifest_latest_artifact(
    manifest: dict[str, Any] | None,
    key: str | None,
    *,
    token: str | None = None,
    kind: str | None = "figure",
    role: str | None = None,
    suffixes: tuple[str, ...] | None = (".jpg", ".jpeg", ".png"),
    directory_hint: str | Path | None = None,
    strict_point_token: bool = False,
) -> Path | None:
    """Return the newest matching manifest artifact, with filesystem fallback still handled by callers."""
    if not key:
        return None
    records = _manifest_artifact_records(
        manifest, key, kind=kind, role=role, suffixes=suffixes
    )
    token_text = str(token or "").strip()
    hint_text = str(directory_hint or "").replace("\\", "/")

    filtered: list[tuple[Path, dict[str, Any]]] = []
    for path, record in records:
        if token_text:
            if strict_point_token:
                token_pattern = re.escape(token_text)
                if re.search(
                    rf"(?<![A-Za-z0-9]){token_pattern}(?![A-Za-z0-9])",
                    path.stem,
                ) is None:
                    continue
            elif token_text not in path.stem:
                continue
        if hint_text:
            parent_text = str(path.parent).replace("\\", "/").rstrip("/")
            hint_norm = hint_text.strip("/")
            if not (parent_text.endswith("/" + hint_norm) or parent_text.endswith(hint_norm)):
                continue
        filtered.append((path, record))
    if not filtered:
        return None
    selected_path, selected_record = max(
        filtered, key=lambda item: item[0].stat().st_mtime
    )
    if active_pinned_analysis_manifest() is not None:
        return _verify_pinned_analysis_artifact(selected_path, selected_record)
    return selected_path if selected_path.exists() else None


def manifest_precheck_warnings(result_root: Path | str | None) -> list[str]:
    """Build concise report-generation warnings from the latest analysis manifest."""
    context = analysis_manifest_context(result_root)
    if not context["available"]:
        return ["analysis manifest not found; report generator will rely on stats/images only"]

    warnings: list[str] = []
    status = str(context.get("status") or "").lower()
    if status and status not in {"ok", "success", "completed"}:
        warnings.append(f"analysis manifest status is {status}")

    for item in context.get("missing_modules", []) or []:
        if not isinstance(item, dict):
            continue
        label = item.get("label") or item.get("key") or "unknown"
        msg = item.get("message") or item.get("error_type") or item.get("status") or ""
        warnings.append(f"module missing/failed: {label} {msg}".strip())

    manifest = context.get("manifest")
    if isinstance(manifest, dict):
        run_preflight = manifest.get("run_preflight")
        if isinstance(run_preflight, dict):
            for item in run_preflight.get("errors", []) or []:
                if item:
                    warnings.append(f"analysis preflight error: {item}")
            for item in run_preflight.get("warnings", []) or []:
                if item:
                    warnings.append(f"analysis preflight warning: {item}")
            for item in run_preflight.get("result_artifact_preflight", []) or []:
                if not isinstance(item, dict):
                    continue
                status_text = str(item.get("status") or "").lower()
                if status_text in {"", "ok"}:
                    continue
                label = item.get("label") or item.get("key") or "result artifact"
                issue_type = item.get("issue_type") or item.get("stale_type") or status_text
                message = item.get("message") or item.get("stats_path") or item.get("artifact_path") or ""
                warnings.append(f"analysis result artifact {status_text}: {label} {issue_type} {message}".strip())
        for path in manifest.get("missing_expected_stats") or manifest.get("missing_stats_files") or []:
            if path:
                warnings.append(f"expected stats missing: {path}")
        for item in manifest.get("warnings", []) or []:
            if item:
                warnings.append(f"analysis warning: {item}")

    deduped: list[str] = []
    seen: set[str] = set()
    for item in warnings:
        if item not in seen:
            seen.add(item)
            deduped.append(item)
    return deduped


def missing_module_summary_items(context: dict[str, Any] | None) -> list[str]:
    if not isinstance(context, dict):
        return []
    items: list[str] = []
    for item in context.get("missing_modules", []) or []:
        if not isinstance(item, dict):
            continue
        label = item.get("label") or item.get("key") or "unknown"
        status = item.get("status") or "missing"
        message = item.get("message") or item.get("error_type") or ""
        if message:
            items.append(f"analysis:{label}:{status}:{message}")
        else:
            items.append(f"analysis:{label}:{status}")
    return items
