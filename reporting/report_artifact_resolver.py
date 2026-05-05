from __future__ import annotations

from pathlib import Path
from typing import Iterable

from artifact_lookup import (
    ArtifactLookupResult,
    latest_file_patterns as shared_latest_file_patterns,
    latest_point_image_patterns as shared_latest_point_image_patterns,
)


DOCX_IMAGE_SUFFIXES = (".jpg", ".jpeg", ".png")


def image_patterns(stem_prefix: str, suffixes: Iterable[str] = DOCX_IMAGE_SUFFIXES) -> list[str]:
    """Build report-safe image patterns for python-docx insertion."""
    return [f"{stem_prefix}*{suffix}" for suffix in suffixes]


def find_latest_file_patterns(
    root: Path,
    configured_dir: str | Path,
    patterns: list[str],
    *,
    recursive: bool = True,
    use_manifest: bool = True,
    kind: str | None = None,
) -> ArtifactLookupResult:
    return shared_latest_file_patterns(
        root,
        configured_dir,
        patterns,
        recursive=recursive,
        use_manifest=use_manifest,
        kind=kind,
    )


def find_latest_file(root: Path, configured_dir: str | Path, pattern: str) -> ArtifactLookupResult:
    return find_latest_file_patterns(root, configured_dir, [pattern], kind=None)


def find_latest_image_patterns(root: Path, configured_dir: str | Path, patterns: list[str]) -> ArtifactLookupResult:
    return find_latest_file_patterns(root, configured_dir, patterns, kind="figure")


def find_latest_image(root: Path, configured_dir: str | Path, stem_prefix: str) -> ArtifactLookupResult:
    return find_latest_image_patterns(root, configured_dir, image_patterns(stem_prefix))


def find_latest_point_image_patterns(
    root: Path,
    configured_dir: str | Path,
    point_id: str,
    patterns: list[str],
    *,
    recursive: bool = True,
) -> ArtifactLookupResult:
    return shared_latest_point_image_patterns(root, configured_dir, point_id, patterns, recursive=recursive)


def find_latest_point_image(root: Path, configured_dir: str | Path, point_id: str, stem_prefix: str) -> ArtifactLookupResult:
    return find_latest_point_image_patterns(root, configured_dir, point_id, image_patterns(stem_prefix))
