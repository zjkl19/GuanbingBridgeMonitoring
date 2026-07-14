from __future__ import annotations

from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any

from analysis_manifest import (
    active_pinned_analysis_manifest,
    analysis_manifest_context,
    pinned_analysis_manifest_scope,
)
from reporting_contract import reporting_contract_context


@dataclass(frozen=True)
class ReportBuildContext:
    template: Path
    config_path: Path | None
    result_root: Path | None
    analysis_root: Path
    stats_root: Path
    fallback_stats_root: Path | None
    image_root: Path
    wim_root: Path | None
    output_dir: Path
    assets_dir: Path
    analysis_manifest_path: Path | None
    analysis_manifest_sha256: str
    require_source_provenance: bool

    @classmethod
    def from_inputs(
        cls,
        *,
        template: Path,
        config_path: Path | None = None,
        result_root: Path | None = None,
        analysis_root: Path | None = None,
        image_root: Path | None = None,
        output_dir: Path | None = None,
        wim_root: Path | None = None,
        assets_subdir: str = "generated_assets",
        default_output_subdir: str = "自动报告",
        analysis_manifest_path: Path | None = None,
        analysis_manifest_sha256: str = "",
        require_source_provenance: bool = False,
    ) -> "ReportBuildContext":
        pinned = active_pinned_analysis_manifest()
        if pinned is not None:
            analysis_manifest_path = pinned.path
            analysis_manifest_sha256 = pinned.sha256
            require_source_provenance = True
        analysis_root = analysis_root or Path(__file__).resolve().parents[1]
        result_root = Path(result_root) if result_root is not None else None
        analysis_root = Path(analysis_root)
        stats_root = result_root if result_root is not None else analysis_root
        fallback_stats_root = (
            None
            if require_source_provenance
            else analysis_root if result_root is not None and result_root != analysis_root else None
        )
        image_root = Path(image_root) if image_root is not None else stats_root
        output_dir = Path(output_dir) if output_dir is not None else stats_root / default_output_subdir
        assets_dir = output_dir / assets_subdir
        output_dir.mkdir(parents=True, exist_ok=True)
        assets_dir.mkdir(parents=True, exist_ok=True)
        return cls(
            template=Path(template),
            config_path=Path(config_path) if config_path is not None else None,
            result_root=result_root,
            analysis_root=analysis_root,
            stats_root=stats_root,
            fallback_stats_root=fallback_stats_root,
            image_root=image_root,
            wim_root=Path(wim_root) if wim_root is not None else None,
            output_dir=output_dir,
            assets_dir=assets_dir,
            analysis_manifest_path=(
                Path(analysis_manifest_path).expanduser().resolve()
                if analysis_manifest_path is not None
                else None
            ),
            analysis_manifest_sha256=str(analysis_manifest_sha256 or "").strip().upper(),
            require_source_provenance=bool(require_source_provenance),
        )

    def analysis_context(self) -> dict[str, Any]:
        with pinned_analysis_manifest_scope(
            self.analysis_manifest_path,
            self.analysis_manifest_sha256,
            require_source_provenance=self.require_source_provenance,
            result_root=self.result_root or self.stats_root,
        ):
            return analysis_manifest_context(self.result_root or self.stats_root)

    def reporting_contract_context(self, analysis_context: dict[str, Any] | None = None) -> dict[str, Any]:
        return reporting_contract_context(self.result_root or self.stats_root, analysis_context)

    def to_manifest_paths(self) -> dict[str, str]:
        payload = asdict(self)
        return {key: str(value) if value is not None else "" for key, value in payload.items()}
