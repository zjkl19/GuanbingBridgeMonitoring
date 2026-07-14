from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
from typing import Any


_META_FIELDS = {"extends", "layers", "includes"}


def _file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest().upper()


def _path_list(value: Any) -> list[str]:
    if isinstance(value, str):
        return [value.strip()] if value.strip() else []
    if isinstance(value, list):
        return [item.strip() for item in value if isinstance(item, str) and item.strip()]
    return []


def _deep_merge(base: Any, overlay: Any) -> Any:
    if isinstance(base, dict) and isinstance(overlay, dict):
        merged = dict(base)
        for key, value in overlay.items():
            merged[key] = _deep_merge(merged[key], value) if key in merged else value
        return merged
    return overlay


def _read_object(path: Path) -> dict[str, Any]:
    payload = json.loads(path.read_text(encoding="utf-8-sig"))
    if not isinstance(payload, dict):
        raise ValueError(f"Config root must be an object: {path}")
    return payload


def _resolve_dependency(parent: Path, value: str) -> Path:
    candidate = Path(value).expanduser()
    if not candidate.is_absolute():
        candidate = parent / candidate
    candidate = candidate.resolve()
    if not candidate.is_file():
        raise FileNotFoundError(f"Config dependency does not exist: {candidate}")
    return candidate


def _load_recursive(path: Path, stack: tuple[Path, ...]) -> tuple[dict[str, Any], set[Path]]:
    path = path.expanduser().resolve()
    if path in stack:
        chain = " -> ".join(str(item) for item in (*stack, path))
        raise ValueError(f"Config layering cycle detected: {chain}")
    if not path.is_file():
        raise FileNotFoundError(f"Config file does not exist: {path}")
    own = _read_object(path)
    dependencies = {path}
    merged: dict[str, Any] = {}
    next_stack = (*stack, path)
    for field in ("extends", "layers"):
        for item in _path_list(own.get(field)):
            dependency = _resolve_dependency(path.parent, item)
            layer, layer_dependencies = _load_recursive(dependency, next_stack)
            merged = _deep_merge(merged, layer)
            dependencies.update(layer_dependencies)

    includes = own.get("includes")
    if isinstance(includes, dict):
        for field_name in sorted(includes):
            included: Any = {}
            has_value = False
            for item in _path_list(includes[field_name]):
                dependency = _resolve_dependency(path.parent, item)
                value = json.loads(dependency.read_text(encoding="utf-8-sig"))
                included = value if not has_value else _deep_merge(included, value)
                has_value = True
                dependencies.add(dependency)
            if has_value:
                own[field_name] = (
                    _deep_merge(included, own[field_name])
                    if field_name in own
                    else included
                )

    own = {key: value for key, value in own.items() if key not in _META_FIELDS}
    return _deep_merge(merged, own), dependencies


def load_layered_config(path: Path) -> tuple[dict[str, Any], tuple[Path, ...]]:
    config, dependencies = _load_recursive(path, ())
    return config, tuple(sorted(dependencies, key=lambda item: item.as_posix().casefold()))


def config_dependency_sha256(path: Path) -> str:
    entry = path.expanduser().resolve()
    _, dependencies = load_layered_config(entry)
    if len(dependencies) == 1:
        return _file_sha256(dependencies[0])
    records = []
    for dependency in dependencies:
        try:
            identity = os.path.relpath(dependency, start=entry.parent)
        except ValueError as exc:
            raise ValueError(
                "Config dependencies must be on the same filesystem volume as the entry config"
            ) from exc
        identity = identity.replace("\\", "/").lower()
        records.append((identity, _file_sha256(dependency).lower()))
    payload = "".join(
        f"{identity}\t{digest}\n" for identity, digest in sorted(records)
    ).encode("utf-8")
    return hashlib.sha256(payload).hexdigest().upper()
