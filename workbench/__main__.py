from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from PySide6.QtGui import QFont
from PySide6.QtWidgets import QApplication

from .main_window import WorkbenchWindow
from .version import app_version


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Bridge monitoring PySide6 workbench")
    parser.add_argument("--project-root", type=Path, default=None)
    parser.add_argument("--profile-id", default=None)
    parser.add_argument("--initial-tab", type=int, default=0)
    parser.add_argument("--job-context", type=Path, default=None)
    parser.add_argument("--smoke-test", action="store_true")
    parser.add_argument("--smoke-output", type=Path, default=None)
    parser.add_argument("--screenshot-output", type=Path, default=None)
    parser.add_argument("--screenshot-tab", type=int, default=0)
    return parser


def smoke_payload(window: WorkbenchWindow) -> dict[str, object]:
    return {
        "ok": True,
        "version": app_version(window.project_root),
        "profile_count": len(window.profiles),
        "tab_count": window.tabs.count(),
        "module_count": len(window.module_checks),
        "alarm_bound_row_count": window.alarm_editor.table.rowCount(),
        "report_gate_locked": not window.open_report_btn.isEnabled(),
    }


def main(argv: list[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    app = QApplication([sys.argv[0]])
    app.setFont(QFont("Microsoft YaHei UI", 9))
    window = WorkbenchWindow(args.project_root)
    if args.profile_id:
        profile_index = window.profile_combo.findData(args.profile_id)
        if profile_index < 0:
            raise SystemExit(f"Unknown profile id: {args.profile_id}")
        window.profile_combo.setCurrentIndex(profile_index)
    if args.job_context:
        window.load_context(args.job_context)
    if 0 <= args.initial_tab < window.tabs.count():
        window.tabs.setCurrentIndex(args.initial_tab)
    if args.smoke_test:
        payload = smoke_payload(window)
        output = json.dumps(payload, ensure_ascii=False, indent=2)
        if args.smoke_output:
            args.smoke_output.parent.mkdir(parents=True, exist_ok=True)
            args.smoke_output.write_text(output, encoding="utf-8")
        print(output)
        window.poll_timer.stop()
        window.close()
        return 0
    if args.screenshot_output:
        args.screenshot_output.parent.mkdir(parents=True, exist_ok=True)
        window.show()
        for tab_index in range(window.tabs.count()):
            window.tabs.setCurrentIndex(tab_index)
            app.processEvents()
        if 0 <= args.screenshot_tab < window.tabs.count():
            window.tabs.setCurrentIndex(args.screenshot_tab)
        for _ in range(5):
            app.processEvents()
        window.repaint()
        app.processEvents()
        screen = window.screen() or app.primaryScreen()
        pixmap = screen.grabWindow(int(window.winId())) if screen is not None else window.grab()
        if pixmap.isNull():
            pixmap = window.grab()
        if not pixmap.save(str(args.screenshot_output)):
            window.poll_timer.stop()
            window.close()
            return 2
        window.poll_timer.stop()
        window.close()
        return 0
    window.show()
    return app.exec()


if __name__ == "__main__":
    raise SystemExit(main())
