from __future__ import annotations

import copy
import os
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path

from workbench.cache_cleanup_settings import (
    CACHE_SOURCE_CLEANUP_CONFIRMATION,
    CACHE_SOURCE_CLEANUP_KEY,
    CACHE_SOURCE_CLEANUP_SUPPORTED_LAYOUTS,
    CacheSourceCleanupSettings,
    cleanup_validation_errors,
)
from workbench.cache_cleanup_preflight import cleanup_root_preflight_errors
from workbench.models import JobContext
from workbench.modules import options_for_modules


ROOT = Path(__file__).resolve().parents[1]


class CacheCleanupSettingsTests(unittest.TestCase):
    def test_default_is_disabled_and_emits_no_task_option(self) -> None:
        settings = CacheSourceCleanupSettings()
        self.assertFalse(settings.enabled)
        self.assertEqual(settings.to_task_option([]), {})

    def test_enabled_setting_requires_cache_module_exact_token_and_no_csv_mutator(self) -> None:
        self.assertIn(
            "预生成分析缓存",
            cleanup_validation_errors(
                ["temperature"],
                enabled=True,
                confirmation=CACHE_SOURCE_CLEANUP_CONFIRMATION,
            )[0],
        )
        self.assertIn(
            CACHE_SOURCE_CLEANUP_CONFIRMATION,
            cleanup_validation_errors(
                ["cache_prebuild"], enabled=True, confirmation="DELETE"
            )[0],
        )
        self.assertTrue(
            cleanup_validation_errors(
                ["cache_prebuild"],
                enabled=True,
                confirmation=f" {CACHE_SOURCE_CLEANUP_CONFIRMATION}",
            )
        )
        for conflict in ("rename_csv", "remove_header", "resample"):
            errors = cleanup_validation_errors(
                ["cache_prebuild", conflict],
                enabled=True,
                confirmation=CACHE_SOURCE_CLEANUP_CONFIRMATION,
            )
            self.assertEqual(len(errors), 1, conflict)
            self.assertIn("不能与", errors[0], conflict)
        self.assertIn(
            "独立预处理任务",
            cleanup_validation_errors(
                ["cache_prebuild", "temperature"],
                enabled=True,
                confirmation=CACHE_SOURCE_CLEANUP_CONFIRMATION,
                data_layout="jlj_daily_export",
            )[0],
        )
        for layout in CACHE_SOURCE_CLEANUP_SUPPORTED_LAYOUTS:
            self.assertEqual(
                cleanup_validation_errors(
                    ["cache_prebuild"],
                    enabled=True,
                    confirmation=CACHE_SOURCE_CLEANUP_CONFIRMATION,
                    data_layout=layout,
                ),
                [],
                layout,
            )
        self.assertTrue(
            cleanup_validation_errors(
                ["cache_prebuild"],
                enabled=True,
                confirmation=CACHE_SOURCE_CLEANUP_CONFIRMATION,
                data_layout="unknown_layout",
            )
        )

    def test_read_only_root_preflight_fails_closed_for_missing_bad_and_complete_archives(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            config = root / "config.json"
            config.write_text("{}", encoding="utf-8")
            self.assertTrue(
                cleanup_root_preflight_errors(
                    root, config, "2026-05-01", "2026-05-01", "dated_folders"
                )
            )

            import zipfile

            for kind in ("波形", "特征值"):
                target = root / "2026-05-01" / kind / "device"
                target.mkdir(parents=True)
                with zipfile.ZipFile(target / f"{kind}.zip", "w") as archive:
                    archive.writestr("POINT.csv", "2026-05-01 00:00:00,1\n")
            extra_waveform = root / "2026-05-01" / "波形" / "device" / "波形2.zip"
            with zipfile.ZipFile(extra_waveform, "w") as archive:
                archive.writestr("POINT2.csv", "2026-05-01 00:00:00,2\n")
            self.assertEqual(
                cleanup_root_preflight_errors(
                    root, config, "2026-05-01", "2026-05-01", "dated_folders"
                ),
                [],
            )
            extra_waveform.write_bytes(b"not-a-zip")
            self.assertTrue(
                cleanup_root_preflight_errors(
                    root, config, "2026-05-01", "2026-05-01", "dated_folders"
                )
            )
            with zipfile.ZipFile(extra_waveform, "w") as archive:
                archive.writestr("C:/escape.csv", "2026-05-01 00:00:00,2\n")
            unsafe_errors = cleanup_root_preflight_errors(
                root, config, "2026-05-01", "2026-05-01", "dated_folders"
            )
            self.assertTrue(unsafe_errors)
            self.assertIn("不安全", "\n".join(unsafe_errors))

    def test_enabled_setting_builds_and_restores_closed_policy(self) -> None:
        payload = CacheSourceCleanupSettings(
            True,
            CACHE_SOURCE_CLEANUP_CONFIRMATION,
            "2026-07-16T01:02:03+08:00",
        ).to_task_option(["cache_prebuild"])
        self.assertEqual(
            payload,
            {
                "enabled": True,
                "mode": "verified_extracted_csv",
                "commit_scope": "day",
                "recovery_policy": "verified_archive",
                "confirmation": CACHE_SOURCE_CLEANUP_CONFIRMATION,
                "confirmed_at": "2026-07-16T01:02:03+08:00",
            },
        )
        restored = CacheSourceCleanupSettings.from_task_options(
            {CACHE_SOURCE_CLEANUP_KEY: payload}
        )
        self.assertTrue(restored.enabled)
        self.assertEqual(restored.confirmation, CACHE_SOURCE_CLEANUP_CONFIRMATION)
        self.assertEqual(restored.confirmed_at, "2026-07-16T01:02:03+08:00")

        incompatible = copy.deepcopy(payload)
        incompatible["recovery_policy"] = "trust_cache"
        failed_closed = CacheSourceCleanupSettings.from_task_options(
            {CACHE_SOURCE_CLEANUP_KEY: incompatible}
        )
        self.assertTrue(failed_closed.enabled)
        self.assertEqual(failed_closed.confirmation, "")
        self.assertFalse(failed_closed.policy_compatible)

    def test_nested_options_round_trip_and_binding_use_full_canonical_json(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            temp = Path(folder)
            config = temp / "config.json"
            config.write_text("{}", encoding="utf-8")
            data_root = temp / "data"
            data_root.mkdir()
            base_options: dict[str, object] = dict(options_for_modules(["cache_prebuild"]))
            base_options[CACHE_SOURCE_CLEANUP_KEY] = {
                "enabled": True,
                "mode": "verified_extracted_csv",
                "commit_scope": "day",
                "recovery_policy": "verified_archive",
                "confirmation": CACHE_SOURCE_CLEANUP_CONFIRMATION,
                "confirmed_at": "2026-07-16T01:02:03+08:00",
            }
            context = JobContext.create(
                project_root=ROOT,
                bridge_id="unit",
                bridge_name="测试桥",
                data_root=data_root,
                start_date="2026-06-01",
                end_date="2026-06-30",
                config_path=config,
                selected_modules=["cache_prebuild"],
                options=base_options,
                now=datetime(2026, 7, 16, tzinfo=timezone.utc),
                job_id="cleanup_binding_unit",
            )
            loaded = JobContext.read(context.write())
            self.assertEqual(loaded.options, base_options)
            self.assertEqual(loaded.analysis_binding(), context.analysis_binding())

            reordered = copy.deepcopy(loaded)
            cleanup = reordered.options[CACHE_SOURCE_CLEANUP_KEY]
            self.assertIsInstance(cleanup, dict)
            reordered.options[CACHE_SOURCE_CLEANUP_KEY] = dict(
                reversed(list(cleanup.items()))
            )
            self.assertEqual(reordered.analysis_binding(), context.analysis_binding())

            changed = copy.deepcopy(loaded)
            changed.options[CACHE_SOURCE_CLEANUP_KEY]["commit_scope"] = "file"
            self.assertNotEqual(changed.analysis_binding(), context.analysis_binding())


os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
try:
    from PySide6.QtCore import QDate
    from PySide6.QtWidgets import QApplication

    from workbench.__main__ import (
        exercise_cache_source_cleanup_contract,
        smoke_payload,
    )
    from workbench.main_window import WorkbenchWindow
except ImportError:  # pragma: no cover - dependency gate
    QApplication = None
    WorkbenchWindow = None


@unittest.skipIf(QApplication is None, "PySide6 is not installed")
class CacheCleanupGuiTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.app = QApplication.instance() or QApplication([])

    def test_controls_default_off_require_cache_and_reset_on_profile_change(self) -> None:
        window = WorkbenchWindow(ROOT)
        try:
            self.assertFalse(window.cache_cleanup_check.isChecked())
            self.assertFalse(window.cache_cleanup_check.isEnabled())
            self.assertFalse(window.cache_cleanup_confirmation_edit.isEnabled())
            self.assertIn("默认关闭", window.cache_cleanup_check.toolTip())
            self.assertIn("原 ZIP", window.cache_cleanup_check.toolTip())

            window.profile_combo.setCurrentIndex(
                window.profile_combo.findData("jiulongjiang")
            )
            window.module_checks["cache_prebuild"].setChecked(True)
            self.assertTrue(window.cache_cleanup_check.isEnabled())
            window.cache_cleanup_check.setChecked(True)
            self.assertTrue(window.cache_cleanup_confirmation_edit.isEnabled())
            window.cache_cleanup_confirmation_edit.setText(
                CACHE_SOURCE_CLEANUP_CONFIRMATION
            )

            current = window.profile_combo.currentIndex()
            window.profile_combo.setCurrentIndex(
                1 if current != 1 else 2
            )
            self.assertFalse(window.cache_cleanup_check.isChecked())
            self.assertFalse(window.cache_cleanup_confirmation_edit.text())
            self.assertFalse(window.module_checks["cache_prebuild"].isChecked())
        finally:
            window.poll_timer.stop()
            window.close()

    def test_all_current_bridge_profiles_expose_same_cleanup_contract(self) -> None:
        window = WorkbenchWindow(ROOT)
        try:
            for profile_id in (
                "guanbing",
                "hongtang",
                "jiulongjiang",
                "shuixianhua",
                "chongyangxi",
                "zhishan",
            ):
                window.profile_combo.setCurrentIndex(
                    window.profile_combo.findData(profile_id)
                )
                for checkbox in window.module_checks.values():
                    checkbox.setChecked(False)
                window.module_checks["cache_prebuild"].setChecked(True)
                self.assertTrue(window.cache_cleanup_check.isEnabled(), profile_id)
                self.assertFalse(window.cache_cleanup_check.isChecked(), profile_id)
                window.cache_cleanup_check.setChecked(True)
                window.cache_cleanup_confirmation_edit.setText(
                    CACHE_SOURCE_CLEANUP_CONFIRMATION
                )
                option = window._task_options(["cache_prebuild"])[
                    CACHE_SOURCE_CLEANUP_KEY
                ]
                self.assertTrue(option["enabled"], profile_id)
                self.assertEqual(
                    option["confirmation"], CACHE_SOURCE_CLEANUP_CONFIRMATION
                )
        finally:
            window.poll_timer.stop()
            window.close()

    def test_smoke_payload_freezes_default_off_and_saved_task_contract(self) -> None:
        window = WorkbenchWindow(ROOT)
        try:
            default_payload = smoke_payload(window)
            self.assertTrue(default_payload["cache_source_cleanup_control_available"])
            self.assertTrue(default_payload["cache_source_cleanup_default_off"])
            self.assertTrue(default_payload["cache_source_cleanup_confirmation_empty"])
            self.assertTrue(default_payload["cache_source_cleanup_confirmation_required"])
            self.assertFalse(default_payload["cache_source_cleanup_task_option_present"])
            self.assertEqual(
                default_payload["cache_source_cleanup_supported_data_layout"],
                "jlj_daily_export",
            )
            self.assertEqual(
                set(default_payload["cache_source_cleanup_supported_data_layouts"]),
                set(CACHE_SOURCE_CLEANUP_SUPPORTED_LAYOUTS),
            )
            self.assertTrue(
                default_payload["cache_source_cleanup_current_layout_supported"]
            )

            window.profile_combo.setCurrentIndex(
                window.profile_combo.findData("jiulongjiang")
            )
            contract = exercise_cache_source_cleanup_contract(window)
            for key in (
                "default_off",
                "default_confirmation_empty",
                "default_task_option_absent",
                "layout_supported",
                "control_enabled_after_cache_selection",
                "confirmation_required",
                "confirmation_matches",
                "policy_complete",
                "saved_context_policy_complete",
                "saved_context_roundtrip",
                "restored_enabled",
                "restored_confirmation_matches",
            ):
                self.assertTrue(contract[key], key)
            self.assertEqual(
                contract["task_option"]["confirmation"],
                CACHE_SOURCE_CLEANUP_CONFIRMATION,
            )
            configured_payload = smoke_payload(window)
            self.assertTrue(configured_payload["cache_source_cleanup_checked"])
            self.assertTrue(
                configured_payload["cache_source_cleanup_current_layout_supported"]
            )
            self.assertTrue(configured_payload["cache_source_cleanup_task_option_present"])
        finally:
            window.poll_timer.stop()
            window.close()

    def test_gui_validation_and_saved_task_round_trip(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            data_root = Path(folder) / "data"
            data_root.mkdir()
            window = WorkbenchWindow(ROOT)
            restored_window = None
            try:
                window.profile_combo.setCurrentIndex(
                    window.profile_combo.findData("jiulongjiang")
                )
                window.data_root_edit.setText(str(data_root))
                window.start_date_edit.setDate(QDate(2026, 5, 1))
                window.end_date_edit.setDate(QDate(2026, 5, 1))
                import zipfile

                with zipfile.ZipFile(
                    data_root / "data_jlj_2026-05-01.zip", "w"
                ) as archive:
                    archive.writestr(
                        "data/jlj/csv/POINT.csv",
                        "ts,value_x\n2026-05-01 00:00:00.000,1\n",
                    )
                for checkbox in window.module_checks.values():
                    checkbox.setChecked(False)
                window.module_checks["cache_prebuild"].setChecked(True)
                window.cache_cleanup_check.setChecked(True)

                errors = window._validate_inputs()
                self.assertTrue(
                    any(CACHE_SOURCE_CLEANUP_CONFIRMATION in item for item in errors)
                )
                window.cache_cleanup_confirmation_edit.setText(
                    CACHE_SOURCE_CLEANUP_CONFIRMATION
                )
                self.assertFalse(
                    [
                        item
                        for item in window._validate_inputs()
                        if CACHE_SOURCE_CLEANUP_CONFIRMATION in item
                    ]
                )

                window.module_checks["resample"].setChecked(True)
                self.assertTrue(
                    any("批量重采样" in item for item in window._validate_inputs())
                )
                window.module_checks["resample"].setChecked(False)

                window._save_context()
                context = window.current_context
                self.assertIsNotNone(context)
                cleanup = context.options[CACHE_SOURCE_CLEANUP_KEY]
                self.assertTrue(cleanup["enabled"])
                self.assertEqual(
                    cleanup["confirmation"], CACHE_SOURCE_CLEANUP_CONFIRMATION
                )
                path = window.current_context_path
                self.assertIsNotNone(path)

                restored_window = WorkbenchWindow(ROOT)
                restored_window.load_context(path)
                self.assertTrue(
                    restored_window.module_checks["cache_prebuild"].isChecked()
                )
                self.assertTrue(restored_window.cache_cleanup_check.isChecked())
                self.assertEqual(
                    restored_window.cache_cleanup_confirmation_edit.text(),
                    CACHE_SOURCE_CLEANUP_CONFIRMATION,
                )
                self.assertEqual(
                    JobContext.read(path).options[CACHE_SOURCE_CLEANUP_KEY], cleanup
                )
                self.assertTrue(
                    restored_window._context_matches_current_inputs(
                        restored_window.current_context
                    )
                )
            finally:
                window.poll_timer.stop()
                window.close()
                if restored_window is not None:
                    restored_window.poll_timer.stop()
                    restored_window.close()


if __name__ == "__main__":
    unittest.main()
