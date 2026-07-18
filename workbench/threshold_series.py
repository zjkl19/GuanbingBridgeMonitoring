from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class PreviewSeries:
    """One display-sized curve shared by manual and Beta threshold tools."""

    module_key: str
    point_id: str
    sensor_type: str
    times: tuple[str, ...]
    values: tuple[float | None, ...]

    @property
    def key(self) -> tuple[str, str]:
        return self.module_key, self.point_id


__all__ = ["PreviewSeries"]
