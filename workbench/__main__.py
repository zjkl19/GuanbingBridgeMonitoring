from __future__ import annotations

import argparse
import json
import sys
import tempfile
from pathlib import Path

from PySide6.QtGui import QFont
from PySide6.QtTest import QTest
from PySide6.QtWidgets import QApplication

from .branding import application_icon, set_windows_app_user_model_id
from .config_layers import config_dependency_sha256
from .main_window import WorkbenchWindow
from .models import file_sha256
from .version import EXECUTABLE_FILENAME, app_version, project_root as default_project_root


CLI_DIAGNOSTIC_LOG = Path(tempfile.gettempdir()) / "BridgeMonitoringWorkbench_cli_error.log"


def _write_cli_diagnostic(message: str) -> None:
    try:
        with CLI_DIAGNOSTIC_LOG.open("a", encoding="utf-8") as stream:
            stream.write(message.rstrip() + "\n")
    except OSError:
        # A malformed command line must still terminate cleanly even if the
        # temporary directory is unavailable.
        pass


class WorkbenchArgumentParser(argparse.ArgumentParser):
    """Argument parser that is safe in a PyInstaller ``--noconsole`` build."""

    def _print_message(self, message: str | None, file: object | None = None) -> None:
        if not message:
            return
        target = file or sys.stdout or sys.stderr
        if target is None:
            _write_cli_diagnostic(message)
            return
        target.write(message)  # type: ignore[attr-defined]

    def error(self, message: str) -> None:
        if sys.stderr is None:
            _write_cli_diagnostic(f"{self.format_usage().rstrip()}\n{self.prog}: error: {message}")
            raise SystemExit(2)
        super().error(message)


def _parser() -> argparse.ArgumentParser:
    parser = WorkbenchArgumentParser(description="Bridge monitoring PySide6 workbench")
    parser.add_argument("--project-root", type=Path, default=None)
    parser.add_argument("--profile-id", default=None)
    parser.add_argument("--initial-tab", type=int, default=0)
    parser.add_argument("--initial-config-tab", type=int, default=0)
    parser.add_argument("--initial-warning-tab", type=int, default=0)
    parser.add_argument("--initial-cleaning-tab", type=int, default=0)
    parser.add_argument("--job-context", type=Path, default=None)
    parser.add_argument("--run-report-job", action="store_true", help=argparse.SUPPRESS)
    parser.add_argument("--report-status", type=Path, default=None, help=argparse.SUPPRESS)
    parser.add_argument("--report-result", type=Path, default=None, help=argparse.SUPPRESS)
    parser.add_argument("--report-runtime-smoke-test", action="store_true", help=argparse.SUPPRESS)
    parser.add_argument("--smoke-test", action="store_true")
    parser.add_argument("--smoke-output", type=Path, default=None)
    parser.add_argument("--screenshot-output", type=Path, default=None)
    parser.add_argument("--screenshot-tab", type=int, default=0)
    parser.add_argument("--demo-auto-threshold-preview", action="store_true")
    parser.add_argument("--show-task-history", action="store_true")
    parser.add_argument("--demo-task-history", action="store_true")
    parser.add_argument("--install-staged-update", action="store_true")
    parser.add_argument("--install-source", type=Path, default=None)
    parser.add_argument("--install-root", type=Path, default=None)
    parser.add_argument("--install-version", default="")
    parser.add_argument("--wait-pid", type=int, default=0)
    parser.add_argument("--restart-after-install", action="store_true")
    parser.add_argument("--install-log", type=Path, default=None)
    return parser


def smoke_payload(window: WorkbenchWindow) -> dict[str, object]:
    profile = window.current_profile
    config_path = Path(window.config_edit.text().strip())
    template_path = Path(window.template_edit.text().strip()) if window.template_edit.text().strip() else None
    config_messages = (
        window.alarm_editor.message_label.text(),
        window.cleaning_editor.message_label.text(),
        window.post_filter_editor.message_label.text(),
        window.offset_editor.message_label.text(),
        window.group_plot_editor.summary_label.text(),
        window.plot_common_editor.summary_label.text(),
        window.spectrum_editor.summary_label.text(),
    )
    organization_logo = window.organization_logo_label.pixmap()
    return {
        "ok": True,
        "executable_filename": EXECUTABLE_FILENAME,
        "ui_font_point_size": window.font().pointSize(),
        "version": app_version(window.project_root),
        "profile_count": len(window.profiles),
        "tab_count": window.tabs.count(),
        "module_count": len(window.module_checks),
        "alarm_bound_row_count": window.alarm_editor.table.rowCount(),
        "effective_warning_row_count": len(window.alarm_editor.effective_rows),
        "warning_subtab_count": window.alarm_editor.inner_tabs.count(),
        "invalid_warning_row_count": sum(
            row.status == "invalid" for row in window.alarm_editor.effective_rows
        ),
        "cleaning_threshold_row_count": window.cleaning_editor.table.rowCount(),
        "cleaning_exclude_editor_available": window.cleaning_editor.cleaning_tabs.count() == 2,
        "cleaning_exclude_range_count": window.cleaning_editor.exclude_table.rowCount(),
        "config_tab_count": window.config_tabs.count(),
        "auto_threshold_module_count": window.auto_threshold_editor.module_list.count(),
        "auto_threshold_preview_enabled": bool(
            window.auto_threshold_editor._options().get("capture_preview_series")
        ),
        "update_backup_management_enabled": window.update_backup_btn.isEnabled(),
        "auto_update_option_available": window.auto_update_check.isEnabled(),
        "auto_update_enabled": window.auto_update_check.isChecked(),
        "profile_matrix_review_enabled": window.profile_matrix_btn.isEnabled(),
        "task_history_enabled": window.history_btn.isEnabled(),
        "task_history_column_count": window.task_history_page.table.columnCount(),
        "offset_correction_row_count": window.offset_editor.table.rowCount(),
        "group_plot_module_count": window.group_plot_editor.module_combo.count(),
        "plot_common_field_count": window.plot_common_editor.table.rowCount(),
        "spectrum_module_count": window.spectrum_editor.module_combo.count(),
        "provenance_column_count": window.provenance_table.columnCount(),
        "report_qc_column_count": window.report_qc_table.columnCount(),
        "report_gate_locked": not window.open_report_btn.isEnabled(),
        "selected_profile_id": profile.bridge_id,
        "selected_profile_name": profile.bridge_name,
        "selected_path_profile_id": (
            window.active_path_profile.profile_id if window.active_path_profile is not None else "custom_or_default"
        ),
        "selected_path_profile_reason": window.path_profile_status_label.text(),
        "window_icon_available": not window.windowIcon().isNull(),
        "organization_logo_available": (
            organization_logo is not None and not organization_logo.isNull()
        ),
        "selected_data_layout": profile.data_layout,
        "selected_report_type": profile.report_type,
        "selected_report_gui_type": profile.report_gui_type,
        "selected_report_capable": bool(profile.report_template and profile.report_gui_type),
        "selected_data_root": window.data_root_edit.text().strip(),
        "data_source_mode_summary": window.data_source_mode_label.text(),
        "selected_start_date": window.start_date_edit.date().toString("yyyy-MM-dd"),
        "selected_end_date": window.end_date_edit.date().toString("yyyy-MM-dd"),
        "selected_modules": window._selected_modules(),
        "selected_config_path": str(config_path.resolve()),
        "selected_config_sha256": config_dependency_sha256(config_path) if config_path.is_file() else "",
        "selected_template_path": str(template_path.resolve()) if template_path else "",
        "selected_template_sha256": file_sha256(template_path) if template_path and template_path.is_file() else "",
        "configuration_load_errors": [
            message for message in config_messages if "失败" in message or "error" in message.lower()
        ],
    }


def main(argv: list[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    if args.report_runtime_smoke_test:
        from .embedded_report import write_report_runtime_smoke

        return write_report_runtime_smoke(args.smoke_output)
    if args.run_report_job:
        if args.job_context is None or args.report_status is None or args.report_result is None:
            raise SystemExit("report worker mode requires job context, status and result paths")
        from .embedded_report import run_embedded_report_job

        return run_embedded_report_job(args.job_context, args.report_status, args.report_result)
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
    set_windows_app_user_model_id()
    app = QApplication([sys.argv[0]])
    app.setFont(QFont("Microsoft YaHei UI", 10))
    icon_root = (args.project_root or default_project_root()).resolve()
    app.setWindowIcon(application_icon(icon_root))
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
    if 0 <= args.initial_warning_tab < window.alarm_editor.inner_tabs.count():
        window.alarm_editor.inner_tabs.setCurrentIndex(args.initial_warning_tab)
    if 0 <= args.initial_cleaning_tab < window.cleaning_editor.cleaning_tabs.count():
        window.cleaning_editor.cleaning_tabs.setCurrentIndex(args.initial_cleaning_tab)
    if args.demo_auto_threshold_preview:
        window.auto_threshold_editor.load_preview_demo()
    if args.demo_task_history:
        window.show_task_history(demo=True)
    elif args.show_task_history:
        window.show_task_history()
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
