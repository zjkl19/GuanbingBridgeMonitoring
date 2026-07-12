from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from PySide6.QtGui import QFont
from PySide6.QtTest import QTest
from PySide6.QtWidgets import QApplication

from .main_window import WorkbenchWindow
from .version import app_version


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Bridge monitoring PySide6 workbench")
    parser.add_argument("--project-root", type=Path, default=None)
    parser.add_argument("--profile-id", default=None)
    parser.add_argument("--initial-tab", type=int, default=0)
    parser.add_argument("--initial-config-tab", type=int, default=0)
    parser.add_argument("--job-context", type=Path, default=None)
    parser.add_argument("--smoke-test", action="store_true")
    parser.add_argument("--smoke-output", type=Path, default=None)
    parser.add_argument("--screenshot-output", type=Path, default=None)
    parser.add_argument("--screenshot-tab", type=int, default=0)
    parser.add_argument("--demo-auto-threshold-preview", action="store_true")
    parser.add_argument("--install-staged-update", action="store_true")
    parser.add_argument("--install-source", type=Path, default=None)
    parser.add_argument("--install-root", type=Path, default=None)
    parser.add_argument("--install-version", default="")
    parser.add_argument("--wait-pid", type=int, default=0)
    parser.add_argument("--restart-after-install", action="store_true")
    parser.add_argument("--install-log", type=Path, default=None)
    return parser


def smoke_payload(window: WorkbenchWindow) -> dict[str, object]:
    return {
        "ok": True,
        "version": app_version(window.project_root),
        "profile_count": len(window.profiles),
        "tab_count": window.tabs.count(),
        "module_count": len(window.module_checks),
        "alarm_bound_row_count": window.alarm_editor.table.rowCount(),
        "cleaning_threshold_row_count": window.cleaning_editor.table.rowCount(),
        "config_tab_count": window.config_tabs.count(),
        "auto_threshold_module_count": window.auto_threshold_editor.module_list.count(),
        "auto_threshold_preview_enabled": bool(
            window.auto_threshold_editor._options().get("capture_preview_series")
        ),
        "update_backup_management_enabled": window.update_backup_btn.isEnabled(),
        "offset_correction_row_count": window.offset_editor.table.rowCount(),
        "group_plot_module_count": window.group_plot_editor.module_combo.count(),
        "plot_common_field_count": window.plot_common_editor.table.rowCount(),
        "spectrum_module_count": window.spectrum_editor.module_combo.count(),
        "provenance_column_count": window.provenance_table.columnCount(),
        "report_qc_column_count": window.report_qc_table.columnCount(),
        "report_gate_locked": not window.open_report_btn.isEnabled(),
    }


def main(argv: list[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    if args.install_staged_update:
        if args.install_source is None or args.install_root is None or not args.install_version:
            raise SystemExit("install mode requires source, root and version")
        from .updater import install_staged_update

        try:
            install_staged_update(
                args.install_source,
                args.install_root,
                args.install_version,
                wait_pid=args.wait_pid,
                restart=args.restart_after_install,
                log_path=args.install_log,
            )
            return 0
        except Exception:
            return 1
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
    if 0 <= args.initial_config_tab < window.config_tabs.count():
        window.config_tabs.setCurrentIndex(args.initial_config_tab)
    if args.demo_auto_threshold_preview:
        window.auto_threshold_editor.load_preview_demo()
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
            QTest.qWait(25)
        if 0 <= args.screenshot_tab < window.tabs.count():
            window.tabs.setCurrentIndex(args.screenshot_tab)
        for _ in range(5):
            app.processEvents()
            QTest.qWait(50)
        window.repaint()
        app.processEvents()
        QTest.qWait(250)
        screen = window.screen() or app.primaryScreen()
        pixmap = window.grab()
        if pixmap.isNull():
            pixmap = screen.grabWindow(int(window.winId())) if screen is not None else window.grab()
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
