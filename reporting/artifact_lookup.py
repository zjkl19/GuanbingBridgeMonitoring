from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

from analysis_manifest import (
    active_pinned_derived_artifact_manifest,
    active_pinned_analysis_manifest,
    analysis_manifest_context,
    derived_manifest_latest_artifact,
    manifest_key_for_dir,
    manifest_latest_artifact,
    manifest_role_for_lookup,
)


DEFAULT_BANNED_PARTS = frozenset({".git", ".venv", "tests", "__pycache__"})


@dataclass(frozen=True)
class ArtifactLookupResult:
    path: Path | None
    debug: dict


def should_skip_search_dir(path: Path, banned_parts: Iterable[str] = DEFAULT_BANNED_PARTS) -> bool:
    banned = set(banned_parts)
    return any(part in banned for part in path.parts)


def resolve_output_dirs(root: Path, configured_dir: str | Path, *, recursive: bool = True) -> list[Path]:
    configured_path = Path(configured_dir)
    candidates: list[Path] = []
    direct = (root / configured_path).resolve()
    if direct.exists() and direct.is_dir():
        candidates.append(direct)

    if recursive:
        target_name = configured_path.name
        if root.exists():
            for found in root.rglob(target_name):
                if not found.is_dir():
                    continue
                resolved = found.resolve()
                if resolved in candidates or should_skip_search_dir(resolved):
                    continue
                candidates.append(resolved)

    candidates.sort(key=lambda p: p.stat().st_mtime if p.exists() else 0, reverse=True)
    return candidates


def filename_has_point_token(path: Path, point_id: str) -> bool:
    token = re.escape(str(point_id))
    return re.search(rf"(?<![A-Za-z0-9]){token}(?![A-Za-z0-9])", path.stem) is not None


def tokens_from_patterns(patterns: list[str]) -> list[str]:
    tokens: list[str] = []
    for pattern in patterns:
        token = pattern.split("*", 1)[0]
        token = Path(token).stem if "." in token and "*" not in token else token
        token = token.strip()
        if token and token not in tokens:
            tokens.append(token)
    return tokens


def suffixes_from_patterns(patterns: list[str]) -> tuple[str, ...] | None:
    suffixes = tuple(
        sorted({Path(pattern.replace("*", "x")).suffix.lower() for pattern in patterns if Path(pattern.replace("*", "x")).suffix})
    )
    return suffixes or None


def latest_file_patterns(
    root: Path,
    configured_dir: str | Path,
    patterns: list[str],
    *,
    point_id: str | None = None,
    point_token_strict: bool = False,
    recursive: bool = True,
    use_manifest: bool = True,
    kind: str | None = None,
) -> ArtifactLookupResult:
    configured_dir_text = str(configured_dir)
    rejected_manifest_collision: Path | None = None
    strict_binding = active_pinned_analysis_manifest()
    context = (
        analysis_manifest_context(root)
        if use_manifest or strict_binding is not None
        else {"available": False, "strict_source_provenance": False}
    )
    if context.get("available"):
        tokens = [str(point_id)] if point_id else tokens_from_patterns(patterns)
        if not tokens:
            tokens = [""]
        for token in tokens:
            manifest_path = manifest_latest_artifact(
                context.get("manifest"),
                manifest_key_for_dir(configured_dir_text),
                token=token or None,
                kind=kind,
                role=manifest_role_for_lookup(configured_dir_text, token),
                suffixes=suffixes_from_patterns(patterns),
                directory_hint=configured_dir_text,
                strict_point_token=point_token_strict,
            )
            if manifest_path is not None:
                if point_token_strict and point_id and not filename_has_point_token(
                    manifest_path, point_id
                ):
                    rejected_manifest_collision = manifest_path
                else:
                    return ArtifactLookupResult(
                        manifest_path,
                        {
                            "image_root": str(root),
                            "configured_dir": configured_dir_text,
                            "point_id": point_id or "",
                            "patterns": patterns,
                            "selected_file": str(manifest_path),
                            "source": "analysis_manifest",
                            "manifest": context.get("path", ""),
                        },
                    )

    derived_binding = active_pinned_derived_artifact_manifest()
    if derived_binding is not None:
        tokens = [str(point_id)] if point_id else tokens_from_patterns(patterns)
        if not tokens:
            tokens = [""]
        for token in tokens:
            derived_path = derived_manifest_latest_artifact(
                root,
                token=token or None,
                kind=kind,
                role=manifest_role_for_lookup(configured_dir_text, token),
                suffixes=suffixes_from_patterns(patterns),
                directory_hint=configured_dir_text,
                strict_point_token=point_token_strict,
            )
            if derived_path is not None:
                return ArtifactLookupResult(
                    derived_path,
                    {
                        "image_root": str(root),
                        "configured_dir": configured_dir_text,
                        "point_id": point_id or "",
                        "patterns": patterns,
                        "selected_file": str(derived_path),
                        "source": "derived_artifact_manifest",
                        "manifest": str(derived_binding.path),
                        "manifest_sha256": derived_binding.sha256,
                    },
                )

    if context.get("strict_source_provenance"):
        return ArtifactLookupResult(
            None,
            {
                "image_root": str(root),
                "configured_dir": configured_dir_text,
                "point_id": point_id or "",
                "patterns": patterns,
                "selected_file": None,
                "source": "pinned_analysis_manifest",
                "manifest": context.get("path", ""),
                "reason": (
                    "No matching artifact is recorded in the pinned analysis manifest; "
                    "filesystem fallback is disabled."
                ),
            },
        )

    resolved_dirs = resolve_output_dirs(root, configured_dir_text, recursive=recursive)
    matched: list[Path] = []
    rejected: list[Path] = []
    for folder in resolved_dirs:
        for pattern in patterns:
            for candidate in folder.glob(pattern):
                if point_token_strict and point_id and not filename_has_point_token(candidate, point_id):
                    rejected.append(candidate)
                    continue
                matched.append(candidate.resolve())
    matched = sorted(set(matched), key=lambda p: p.stat().st_mtime, reverse=True)
    debug = {
        "image_root": str(root),
        "configured_dir": configured_dir_text,
        "point_id": point_id or "",
        "resolved_dirs": [str(p) for p in resolved_dirs],
        "patterns": patterns,
        "matched_files": [str(p) for p in matched[:10]],
        "selected_file": str(matched[0]) if matched else None,
    }
    if rejected:
        debug["rejected_prefix_collisions"] = [str(p.resolve()) for p in rejected[:10]]
    if rejected_manifest_collision is not None:
        debug["rejected_manifest_prefix_collision"] = str(
            rejected_manifest_collision.resolve()
        )
    return ArtifactLookupResult(matched[0] if matched else None, debug)


def latest_image_patterns(root: Path, configured_dir: str | Path, patterns: list[str], *, recursive: bool = True) -> ArtifactLookupResult:
    return latest_file_patterns(root, configured_dir, patterns, recursive=recursive, kind=None)


def latest_point_image_patterns(
    root: Path,
    configured_dir: str | Path,
    point_id: str,
    patterns: list[str],
    *,
    recursive: bool = True,
) -> ArtifactLookupResult:
    return latest_file_patterns(
        root,
        configured_dir,
        patterns,
        point_id=point_id,
        point_token_strict=True,
        recursive=recursive,
        kind="figure",
    )
