from __future__ import annotations

from PySide6.QtWidgets import QPushButton


DANGER_ACTION_STYLE = """
QPushButton[destructiveAction="true"] {
    border: 1px solid #8f1d1d;
    border-radius: 3px;
    padding: 5px 12px;
    font-weight: 700;
}
QPushButton[destructiveAction="true"]:enabled {
    background-color: #a61b1b;
    color: white;
}
QPushButton[destructiveAction="true"]:enabled:hover {
    background-color: #861515;
    border-color: #701010;
}
QPushButton[destructiveAction="true"]:enabled:pressed {
    background-color: #651010;
    border-color: #520b0b;
}
QPushButton[destructiveAction="true"]:disabled {
    background-color: #d5d7da;
    border-color: #b8bcc1;
    color: #777c82;
}
"""


def apply_danger_action_style(button: QPushButton) -> None:
    """Apply the shared visual contract for cooperative stop actions."""

    button.setProperty("destructiveAction", True)
    button.setStyleSheet(DANGER_ACTION_STYLE)
