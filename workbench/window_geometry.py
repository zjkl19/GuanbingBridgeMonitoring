from __future__ import annotations

from collections.abc import Sequence

from PySide6.QtCore import QPoint, QRect, QSize


DEFAULT_MINIMUM_SIZE = QSize(960, 640)


def _positive_rect(rect: QRect | None) -> bool:
    return bool(rect is not None and rect.width() > 0 and rect.height() > 0)


def _intersection_area(first: QRect, second: QRect) -> int:
    intersection = first.intersected(second)
    return max(0, intersection.width()) * max(0, intersection.height())


def saved_geometry_is_legal(
    saved: QRect | None,
    available_geometries: Sequence[QRect],
    *,
    minimum_visible: QSize = QSize(96, 48),
) -> bool:
    """Return whether a saved window still has a usable area on any screen."""

    if not _positive_rect(saved) or not available_geometries:
        return False
    assert saved is not None
    required_width = min(saved.width(), max(1, minimum_visible.width()))
    required_height = min(saved.height(), max(1, minimum_visible.height()))
    for available in available_geometries:
        intersection = saved.intersected(available)
        if (
            intersection.width() >= required_width
            and intersection.height() >= required_height
        ):
            return True
    return False


def target_screen_geometry(
    available_geometries: Sequence[QRect],
    *,
    saved: QRect | None = None,
    anchor: QPoint | None = None,
) -> QRect:
    """Select the screen containing the saved window or the current pointer."""

    if not available_geometries:
        return QRect(0, 0, 1280, 720)
    if _positive_rect(saved):
        assert saved is not None
        return max(
            available_geometries,
            key=lambda available: _intersection_area(saved, available),
        )
    if anchor is not None:
        for available in available_geometries:
            if available.contains(anchor):
                return QRect(available)
    return QRect(available_geometries[0])


def fit_window_geometry(
    available_geometries: Sequence[QRect],
    *,
    saved: QRect | None = None,
    anchor: QPoint | None = None,
    scale: float = 0.9,
    minimum_size: QSize = DEFAULT_MINIMUM_SIZE,
) -> QRect:
    """Restore and clamp a saved window, or create a centered 90% window.

    The function only consumes geometry values, so multi-monitor and DPI
    behavior can be covered without constructing a native window.
    """

    screens = tuple(QRect(item) for item in available_geometries if _positive_rect(item))
    legal_saved = saved_geometry_is_legal(saved, screens)
    screen = target_screen_geometry(
        screens,
        saved=saved if legal_saved else None,
        anchor=anchor,
    )

    if legal_saved:
        assert saved is not None
        width = min(saved.width(), screen.width())
        height = min(saved.height(), screen.height())
        x = min(max(saved.x(), screen.left()), screen.right() - width + 1)
        y = min(max(saved.y(), screen.top()), screen.bottom() - height + 1)
        return QRect(x, y, width, height)

    bounded_scale = min(1.0, max(0.1, float(scale)))
    width = min(
        screen.width(),
        max(minimum_size.width(), round(screen.width() * bounded_scale)),
    )
    height = min(
        screen.height(),
        max(minimum_size.height(), round(screen.height() * bounded_scale)),
    )
    x = screen.left() + (screen.width() - width) // 2
    y = screen.top() + (screen.height() - height) // 2
    return QRect(x, y, width, height)
