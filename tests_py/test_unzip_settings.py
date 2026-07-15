from __future__ import annotations

import json
import math
import os
import tempfile
import unittest
from pathlib import Path

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

from workbench.unzip_settings import (
    AUTO_MAX_WORKERS,
    AUTO_TOKEN,
    DEFAULT_WORKERS,
    MAX_CUSTOM_WORKERS,
    PRESET_WORKERS,
    UnzipWorkerConfigError,
    apply_unzip_worker_setting,
    normalize_unzip_worker_setting,
    unzip_worker_setting_from_config,
)

try:
    from PySide6.QtWidgets import QApplication

    from workbench.preprocess_config_tab import CUSTOM_TOKEN, UnzipSettingsEditorWidget
except ImportError:  # pragma: no cover - dependency gate
    QApplication = None
    UnzipSettingsEditorWidget = None
    CUSTOM_TOKEN = "__custom__"


class UnzipWorkerContractTests(unittest.TestCase):
    def test_python_constants_match_shared_matlab_contract(self) -> None:
        root = Path(__file__).resolve().parents[1]
        contract = json.loads(
            (root / "tests" / "fixtures" / "unzip_worker_contract.json").read_text(
                encoding="utf-8"
            )
        )
        self.assertEqual(contract["default_workers"], DEFAULT_WORKERS)
        self.assertEqual(contract["auto_token"], AUTO_TOKEN)
        self.assertEqual(contract["auto_max_workers"], AUTO_MAX_WORKERS)
        self.assertEqual(contract["max_custom_workers"], MAX_CUSTOM_WORKERS)
        self.assertEqual(tuple(contract["preset_workers"]), PRESET_WORKERS)
        self.assertEqual(
            contract["summary_fields"],
            [
                "worker_mode",
                "requested_workers",
                "resolved_workers",
                "effective_workers",
                "parallel_fallback",
                "parallel_fallback_reason",
            ],
        )

    def test_missing_and_null_retain_legacy_serial_default(self) -> None:
        expected = normalize_unzip_worker_setting(DEFAULT_WORKERS)
        self.assertEqual(normalize_unzip_worker_setting(), expected)
        self.assertEqual(unzip_worker_setting_from_config({}), expected)
        self.assertEqual(
            unzip_worker_setting_from_config({"preprocessing": {"unzip": {"max_workers": None}}}),
            expected,
        )

    def test_auto_and_legacy_numeric_values_are_normalized_without_coercion(self) -> None:
        automatic = normalize_unzip_worker_setting(" AUTO ")
        self.assertEqual(automatic.mode, "auto")
        self.assertEqual(automatic.requested_workers, AUTO_TOKEN)
        self.assertEqual(automatic.worker_limit, AUTO_MAX_WORKERS)
        for value in (1, 2, 4, 7, 64, 2.0):
            setting = normalize_unzip_worker_setting(value)
            self.assertEqual(setting.mode, "fixed")
            self.assertEqual(setting.requested_workers, int(value))
            self.assertEqual(setting.worker_limit, int(value))

    def test_invalid_values_fail_instead_of_being_silently_truncated(self) -> None:
        for value in (0, -1, 1.5, 65, True, False, "2", "parallel", [], {}, math.inf):
            with self.subTest(value=value), self.assertRaises(UnzipWorkerConfigError):
                normalize_unzip_worker_setting(value)
        with self.assertRaisesRegex(UnzipWorkerConfigError, "preprocessing 必须"):
            unzip_worker_setting_from_config({"preprocessing": []})
        with self.assertRaisesRegex(UnzipWorkerConfigError, "preprocessing.unzip 必须"):
            unzip_worker_setting_from_config({"preprocessing": {"unzip": []}})

    def test_apply_changes_only_unzip_worker_field_and_does_not_mutate_source(self) -> None:
        source = {
            "coverage": {"gap_mode": "connect"},
            "defaults": {"acceleration": {"thresholds": {"min": -0.5, "max": 0.5}}},
            "offset_correction": {"acceleration": {"mode": "daily_median"}},
            "preprocessing": {"unzip": {"min_free_gib": 20}, "other": {"enabled": True}},
        }
        original = json.loads(json.dumps(source))
        updated = apply_unzip_worker_setting(source, AUTO_TOKEN)

        self.assertEqual(source, original)
        self.assertEqual(updated["coverage"], source["coverage"])
        self.assertEqual(updated["defaults"], source["defaults"])
        self.assertEqual(updated["offset_correction"], source["offset_correction"])
        self.assertEqual(updated["preprocessing"]["other"], source["preprocessing"]["other"])
        self.assertEqual(updated["preprocessing"]["unzip"]["min_free_gib"], 20)
        self.assertEqual(updated["preprocessing"]["unzip"]["max_workers"], AUTO_TOKEN)


@unittest.skipIf(QApplication is None, "PySide6 is not installed")
class UnzipSettingsEditorWidgetTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.app = QApplication.instance() or QApplication([])

    def test_widget_exposes_auto_presets_and_custom_and_builds_exact_payload(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "config.json"
            payload = {"bridge_name": "unit", "preprocessing": {"unzip": {"max_workers": 7}}}
            path.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")
            widget = UnzipSettingsEditorWidget()
            try:
                widget.load_path(path)
                self.assertEqual(widget.mode_combo.count(), 5)
                self.assertEqual(widget.mode_combo.currentData(), CUSTOM_TOKEN)
                self.assertEqual(widget.custom_workers.value(), 7)

                widget.mode_combo.setCurrentIndex(widget.mode_combo.findData(AUTO_TOKEN))
                updated = widget.build_payload()
                self.assertEqual(
                    updated["preprocessing"]["unzip"]["max_workers"], AUTO_TOKEN
                )
                self.assertEqual(updated["bridge_name"], "unit")

                widget.mode_combo.setCurrentIndex(widget.mode_combo.findData(4))
                self.assertEqual(widget.current_setting().requested_workers, 4)
                self.assertFalse(widget.custom_workers.isVisible())
            finally:
                widget.close()

    def test_all_catalog_profiles_preserve_implicit_serial_default_on_noop(self) -> None:
        root = Path(__file__).resolve().parents[1]
        profiles = json.loads(
            (root / "config" / "bridge_profiles.json").read_text(encoding="utf-8-sig")
        )["profiles"]
        self.assertTrue(profiles)
        for profile in profiles:
            with self.subTest(profile=profile["bridge_id"]):
                path = root / profile["default_config"]
                original = json.loads(path.read_text(encoding="utf-8-sig"))
                widget = UnzipSettingsEditorWidget()
                try:
                    widget.load_path(path)
                    self.assertEqual(widget.build_payload(), original)
                finally:
                    widget.close()


if __name__ == "__main__":
    unittest.main()
