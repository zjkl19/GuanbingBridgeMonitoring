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
from .cache_cleanup_settings import (
    CACHE_SOURCE_CLEANUP_CONFIRMATION,
    CACHE_SOURCE_CLEANUP_KEY,
    CACHE_SOURCE_CLEANUP_MODE,
    CACHE_SOURCE_CLEANUP_RECOVERY,
    CACHE_SOURCE_CLEANUP_SCOPE,
    CACHE_SOURCE_CLEANUP_SUPPORTED_LAYOUTS,
)
from .config_layers import config_dependency_sha256
from .main_window import WorkbenchWindow
from .models import file_sha256
from .version import (
    APP_DISPLAY_NAME,
    EXECUTABLE_FILENAME,
    SUPPORTED_EXECUTABLE_FILENAMES,
    app_version,
    project_root as default_project_root,
)


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
    parser.add_argument("--report-launch-id", default="", help=argparse.SUPPRESS)
    parser.add_argument("--report-runtime-smoke-test", action="store_true", help=argparse.SUPPRESS)
    parser.add_argument("--smoke-test", action="store_true")
    parser.add_argument("--smoke-output", type=Path, default=None)
    parser.add_argument("--screenshot-output", type=Path, default=None)
    parser.add_argument("--screenshot-tab", type=int, default=0)
    parser.add_argument("--demo-auto-threshold-preview", action="store_true")
    parser.add_argument("--demo-cache-source-cleanup", action="store_true", help=argparse.SUPPRESS)
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


def cache_source_cleanup_payload(window: WorkbenchWindow) -> dict[str, object]:
    """Return the task-scoped destructive-cleanup state without mutating it."""

    checked = window.cache_cleanup_check.isChecked()
    confirmation = window.cache_cleanup_confirmation_edit.text()
    selected = window._selected_modules()
    task_option: dict[str, object] = {}
    if checked and confirmation == CACHE_SOURCE_CLEANUP_CONFIRMATION:
        try:
            candidate = window._task_options(selected).get(CACHE_SOURCE_CLEANUP_KEY, {})
        except ValueError:
            candidate = {}
        if isinstance(candidate, dict):
            task_option = candidate
    return {
        "control_available": hasattr(window, "cache_cleanup_check"),
        "checked": checked,
        "default_off": not checked,
        "confirmation_empty": confirmation == "",
        "confirmation_required": (
            window.cache_cleanup_confirmation_edit.placeholderText()
            == CACHE_SOURCE_CLEANUP_CONFIRMATION
        ),
        "confirmation_matches": confirmation == CACHE_SOURCE_CLEANUP_CONFIRMATION,
        # Keep the original singular field for release-manifest readers that
        # predate multi-layout cleanup, and publish the authoritative matrix
        # in the new plural field.
        "supported_data_layout": "jlj_daily_export",
        "supported_data_layouts": sorted(CACHE_SOURCE_CLEANUP_SUPPORTED_LAYOUTS),
        "current_layout_supported": (
            window.current_profile.data_layout in CACHE_SOURCE_CLEANUP_SUPPORTED_LAYOUTS
        ),
        "control_enabled": window.cache_cleanup_check.isEnabled(),
        "task_option_present": bool(task_option),
        "task_option": task_option,
    }


def exercise_cache_source_cleanup_contract(window: WorkbenchWindow) -> dict[str, object]:
    """Exercise opt-in, policy serialization and saved-task restoration in place."""

    if window.current_profile.data_layout not in CACHE_SOURCE_CLEANUP_SUPPORTED_LAYOUTS:
        raise ValueError("cache cleanup demo requires an archive-backed supported layout")
    default_state = cache_source_cleanup_payload(window)

    for checkbox in window.module_checks.values():
        checkbox.setChecked(False)
    window.module_checks["cache_prebuild"].setChecked(True)
    control_enabled_after_cache_selection = window.cache_cleanup_check.isEnabled()
    window.cache_cleanup_check.setChecked(True)
    window.cache_cleanup_confirmation_edit.setText(CACHE_SOURCE_CLEANUP_CONFIRMATION)
    configured_state = cache_source_cleanup_payload(window)
    option = configured_state["task_option"]
    def policy_is_complete(value: object) -> bool:
        return bool(
            isinstance(value, dict)
            and value.get("enabled") is True
            and value.get("mode") == CACHE_SOURCE_CLEANUP_MODE
            and value.get("commit_scope") == CACHE_SOURCE_CLEANUP_SCOPE
            and value.get("recovery_policy") == CACHE_SOURCE_CLEANUP_RECOVERY
            and value.get("confirmation") == CACHE_SOURCE_CLEANUP_CONFIRMATION
            and str(value.get("confirmed_at") or "")
        )

    def stable_policy(value: object) -> tuple[object, ...]:
        if not isinstance(value, dict):
            return ()
        return tuple(
            value.get(key)
            for key in (
                "enabled",
                "mode",
                "commit_scope",
                "recovery_policy",
                "confirmation",
            )
        )

    policy_complete = policy_is_complete(option)

    with tempfile.TemporaryDirectory(prefix="workbench_cleanup_contract_") as folder:
        context_path = Path(folder) / "job_context.json"
        window._build_context().write(context_path)
        saved_option = json.loads(context_path.read_text(encoding="utf-8"))["options"].get(
            CACHE_SOURCE_CLEANUP_KEY, {}
        )
        window.cache_cleanup_check.setChecked(False)
        window.cache_cleanup_confirmation_edit.clear()
        window.module_checks["cache_prebuild"].setChecked(False)
        window.load_context(context_path)
        restored_state = cache_source_cleanup_payload(window)

    return {
        "default_off": bool(default_state["default_off"]),
        "default_confirmation_empty": bool(default_state["confirmation_empty"]),
        "default_task_option_absent": not bool(default_state["task_option_present"]),
        "layout_supported": bool(configured_state["current_layout_supported"]),
        "control_enabled_after_cache_selection": control_enabled_after_cache_selection,
        "confirmation_required": bool(configured_state["confirmation_required"]),
        "confirmation_matches": bool(configured_state["confirmation_matches"]),
        "policy_complete": policy_complete,
        "saved_context_policy_complete": (
            policy_is_complete(saved_option)
            and stable_policy(saved_option) == stable_policy(option)
        ),
        "saved_context_roundtrip": (
            restored_state["checked"] is True
            and restored_state["confirmation_matches"] is True
            and policy_is_complete(restored_state["task_option"])
            and stable_policy(restored_state["task_option"])
            == stable_policy(saved_option)
            and window._context_matches_current_inputs(window.current_context)
        ),
        "restored_enabled": bool(restored_state["checked"]),
        "restored_confirmation_matches": bool(restored_state["confirmation_matches"]),
        "task_option": saved_option,
    }


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
        window.unzip_settings_editor.message_label.text(),
    )
    organization_logo = window.organization_logo_label.pixmap()
    screen = window.screen() or QApplication.primaryScreen()
    cleanup = cache_source_cleanup_payload(window)
    return {
        "ok": True,
        "app_display_name": APP_DISPLAY_NAME,
        "executable_filename": EXECUTABLE_FILENAME,
        "supported_executable_filenames": list(SUPPORTED_EXECUTABLE_FILENAMES),
        "ui_font_point_size": window.font().pointSize(),
        "ui_font_family": window.font().family(),
        "screen_logical_dpi": screen.logicalDotsPerInch() if screen is not None else 0.0,
        "device_pixel_ratio": window.devicePixelRatioF(),
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
        "manual_threshold_controls_available": (
            window.cleaning_editor.threshold_band_button.isEnabled()
            and window.cleaning_editor.lower_box_threshold_button.isEnabled()
            and window.cleaning_editor.upper_box_threshold_button.isEnabled()
        ),
        "threshold_band_control_available": bool(
            window.cleaning_editor.threshold_band_button.isEnabled()
        ),
        "box_threshold_controls_available": bool(
            window.cleaning_editor.lower_box_threshold_button.isEnabled()
            and window.cleaning_editor.upper_box_threshold_button.isEnabled()
        ),
        "lower_box_threshold_control_available": bool(
            window.cleaning_editor.lower_box_threshold_button.isEnabled()
        ),
        "upper_box_threshold_control_available": bool(
            window.cleaning_editor.upper_box_threshold_button.isEnabled()
        ),
        "config_tab_count": window.config_tabs.count(),
        "auto_threshold_module_count": window.auto_threshold_editor.module_list.count(),
        "auto_threshold_preview_enabled": bool(
            window.auto_threshold_editor._options().get("capture_curve_records")
        ),
        "update_backup_management_enabled": window.update_backup_btn.isEnabled(),
        "auto_update_option_available": window.auto_update_check.isEnabled(),
        "auto_update_enabled": window.auto_update_check.isChecked(),
        "profile_matrix_review_enabled": window.profile_matrix_btn.isEnabled(),
        "task_history_enabled": window.history_btn.isEnabled(),
        "task_history_column_count": window.task_history_page.table.columnCount(),
        "analysis_result_location_visible": bool(
            window.analysis_result_path_label.text().strip()
        ),
        "analysis_result_open_control_available": bool(
            window.open_analysis_result_button is not None
            and window.open_analysis_stats_button is not None
            and window.open_analysis_logs_button is not None
        ),
        "threshold_preview_auto_locator_available": bool(
            window.cleaning_editor.preview_context_provider is not None
        ),
        "offset_correction_row_count": window.offset_editor.table.rowCount(),
        "offset_correction_column_count": window.offset_editor.table.columnCount(),
        "offset_effective_range_seconds_available": (
            window.offset_editor.table.horizontalHeaderItem(5).text() == "生效开始时间"
            and window.offset_editor.table.horizontalHeaderItem(6).text() == "生效结束时间"
            and window.offset_editor.edit_effective_range_button.isEnabled()
        ),
        "group_plot_module_count": window.group_plot_editor.module_combo.count(),
        "plot_common_field_count": window.plot_common_editor.table.rowCount(),
        "gap_override_column_count": window.plot_common_editor.gap_table.columnCount(),
        "spectrum_module_count": window.spectrum_editor.module_combo.count(),
        "unzip_worker_setting": window.unzip_settings_editor.requested_value(),
        "unzip_settings_available": window.unzip_settings_editor.isEnabled(),
        "cache_source_cleanup_control_available": cleanup["control_available"],
        "cache_source_cleanup_checked": cleanup["checked"],
        "cache_source_cleanup_default_off": cleanup["default_off"],
        "cache_source_cleanup_confirmation_empty": cleanup["confirmation_empty"],
        "cache_source_cleanup_confirmation_required": cleanup["confirmation_required"],
        "cache_source_cleanup_confirmation_matches": cleanup["confirmation_matches"],
        "cache_source_cleanup_supported_data_layout": cleanup["supported_data_layout"],
        "cache_source_cleanup_supported_data_layouts": cleanup["supported_data_layouts"],
        "cache_source_cleanup_current_layout_supported": cleanup["current_layout_supported"],
        "cache_source_cleanup_control_enabled": cleanup["control_enabled"],
        "cache_source_cleanup_task_option_present": cleanup["task_option_present"],
        "cache_source_cleanup_contract": getattr(
            window, "_cache_source_cleanup_smoke_contract", {}
        ),
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

        return run_embedded_report_job(
            args.job_context,
            args.report_status,
            args.report_result,
            args.report_launch_id,
        )
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
    if args.demo_cache_source_cleanup:
        window._cache_source_cleanup_smoke_contract = exercise_cache_source_cleanup_contract(
            window
        )
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
