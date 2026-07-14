from __future__ import annotations

import json
import os
import tempfile
import unittest
from pathlib import Path

from workbench.manifest import find_latest_manifest, load_manifest_summary, manifest_context_issues


class WorkbenchManifestTests(unittest.TestCase):
    def test_manifest_summary_normalizes_module_records(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "analysis_manifest_1.json"
            path.write_text(json.dumps({
                "status": "ok",
                "artifact_count": 12,
                "bridge_profile": {"bridge_id": "hongtang"},
                "run_request": {
                    "data_root": str(Path(folder) / "data"),
                    "start_date": "2026-04-01",
                    "end_date": "2026-06-30"
                },
                "module_results": [
                    {"key": "temperature", "label": "温度", "status": "ok", "elapsed_sec": 1.2, "stats_path": "temp.xlsx"},
                    {"key": "wind", "label": "风", "status": "failed", "message": "missing source"},
                ],
            }, ensure_ascii=False), encoding="utf-8")
            summary = load_manifest_summary(path)
            self.assertEqual(summary.status, "ok")
            self.assertEqual(summary.artifact_count, 12)
            self.assertEqual(len(summary.modules), 2)
            self.assertEqual(summary.failed_modules[0].key, "wind")
            self.assertEqual(summary.missing_selected_modules(["temperature", "wind"]), ())
            self.assertEqual(summary.missing_selected_modules(["temperature", "strain"]), ("strain",))
            self.assertEqual(summary.bridge_id, "hongtang")
            self.assertEqual(
                manifest_context_issues(
                    summary,
                    bridge_id="hongtang",
                    data_root=Path(folder) / "data",
                    start_date="2026-04-01",
                    end_date="2026-06-30",
                ),
                [],
            )
            issues = manifest_context_issues(
                summary,
                bridge_id="zhishan",
                data_root=Path(folder) / "other",
                start_date="2026-05-01",
                end_date="2026-05-31",
            )
            self.assertEqual(len(issues), 4)

    def test_manifest_context_binds_config_path_and_hash_fail_closed(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            config = root / "config.json"
            config.write_text("{}", encoding="utf-8")
            summary_path = root / "analysis_manifest.json"
            summary_path.write_text(json.dumps({
                "status": "ok",
                "bridge_profile": {"bridge_id": "guanbing"},
                "run_request": {
                    "data_root": str(root),
                    "start_date": "2026-06-01",
                    "end_date": "2026-06-30",
                    "config_path": str(config),
                },
            }), encoding="utf-8")
            summary = load_manifest_summary(summary_path)
            issues = manifest_context_issues(
                summary,
                bridge_id="guanbing",
                data_root=root,
                start_date="2026-06-01",
                end_date="2026-06-30",
                config_path=config,
                config_sha256="A" * 64,
            )
            self.assertTrue(any("配置版本不一致" in issue for issue in issues))

    def test_find_latest_manifest_uses_run_logs(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            logs = root / "run_logs"
            logs.mkdir()
            first = logs / "analysis_manifest_1.json"
            second = logs / "analysis_manifest_2.json"
            first.write_text("{}", encoding="utf-8")
            second.write_text("{}", encoding="utf-8")
            first.touch()
            second.touch()
            self.assertIn(find_latest_manifest(root), {first, second})

    def test_find_latest_manifest_prefers_compatible_complete_run_over_newer_repair(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            logs = root / "run_logs"
            logs.mkdir()
            complete = logs / "analysis_manifest_complete.json"
            repair = logs / "analysis_manifest_repair.json"
            unrelated = logs / "analysis_manifest_unrelated.json"

            def write_manifest(path: Path, *, bridge: str, modules: list[str]) -> None:
                path.write_text(json.dumps({
                    "status": "ok",
                    "bridge_profile": {"bridge_id": bridge},
                    "run_request": {
                        "data_root": str(root),
                        "start_date": "2026-05-26",
                        "end_date": "2026-05-28",
                    },
                    "module_results": [
                        {"key": key, "label": key, "status": "ok"}
                        for key in modules
                    ],
                }), encoding="utf-8")

            selected = ["temperature", "humidity", "acceleration"]
            write_manifest(complete, bridge="guanbing", modules=selected)
            write_manifest(repair, bridge="guanbing", modules=["acceleration"])
            write_manifest(unrelated, bridge="hongtang", modules=selected)
            os.utime(complete, (1, 1))
            os.utime(repair, (2, 2))
            os.utime(unrelated, (3, 3))

            self.assertEqual(find_latest_manifest(root), unrelated)
            self.assertEqual(
                find_latest_manifest(
                    root,
                    bridge_id="guanbing",
                    start_date="2026-05-26",
                    end_date="2026-05-28",
                    selected_modules=selected,
                    successful_only=True,
                ),
                complete,
            )

    def test_find_latest_manifest_skips_failed_or_invalid_compatible_candidates(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            logs = root / "run_logs"
            logs.mkdir()
            complete = logs / "analysis_manifest_complete.json"
            failed = logs / "analysis_manifest_failed.json"
            invalid = logs / "analysis_manifest_invalid.json"
            payload = {
                "status": "ok",
                "bridge_profile": {"bridge_id": "guanbing"},
                "run_request": {
                    "data_root": str(root),
                    "start_date": "2026-05-26",
                    "end_date": "2026-05-28",
                },
                "module_results": [
                    {"key": "temperature", "status": "ok"},
                    {"key": "acceleration", "status": "ok"},
                ],
            }
            complete.write_text(json.dumps(payload), encoding="utf-8")
            failed_payload = dict(payload)
            failed_payload["module_results"] = [
                {"key": "temperature", "status": "ok"},
                {"key": "acceleration", "status": "failed"},
            ]
            failed.write_text(json.dumps(failed_payload), encoding="utf-8")
            invalid.write_bytes(b"\xff\xfe\xfa")
            os.utime(complete, (1, 1))
            os.utime(failed, (2, 2))
            os.utime(invalid, (3, 3))

            self.assertEqual(
                find_latest_manifest(
                    root,
                    bridge_id="guanbing",
                    start_date="2026-05-26",
                    end_date="2026-05-28",
                    selected_modules=["temperature", "acceleration"],
                    successful_only=True,
                ),
                complete,
            )

    def test_find_latest_manifest_fails_closed_when_context_fields_are_missing(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            logs = root / "run_logs"
            logs.mkdir()
            complete = logs / "analysis_manifest_complete.json"
            contextless = logs / "analysis_manifest_contextless.json"
            complete.write_text(json.dumps({
                "status": "ok",
                "bridge_profile": {"bridge_id": "guanbing"},
                "run_request": {
                    "data_root": str(root),
                    "start_date": "2026-05-26",
                    "end_date": "2026-05-28",
                },
                "module_results": [{"key": "acceleration", "status": "ok"}],
            }), encoding="utf-8")
            contextless.write_text(json.dumps({
                "status": "ok",
                "module_results": [{"key": "acceleration", "status": "ok"}],
            }), encoding="utf-8")
            os.utime(complete, (1, 1))
            os.utime(contextless, (2, 2))

            self.assertEqual(
                find_latest_manifest(
                    root,
                    bridge_id="guanbing",
                    start_date="2026-05-26",
                    end_date="2026-05-28",
                    selected_modules=["acceleration"],
                    successful_only=True,
                ),
                complete,
            )

    def test_find_latest_manifest_filters_config_but_unfiltered_keeps_legacy_behavior(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            logs = root / "run_logs"
            logs.mkdir()
            config = root / "config.json"
            config.write_text("{}", encoding="utf-8")
            compatible = logs / "analysis_manifest_compatible.json"
            stale = logs / "analysis_manifest_stale.json"

            def payload(config_hash: str) -> dict:
                return {
                    "status": "ok",
                    "bridge_profile": {"bridge_id": "guanbing"},
                    "run_request": {
                        "data_root": str(root),
                        "start_date": "2026-06-01",
                        "end_date": "2026-06-30",
                        "config_path": str(config),
                        "config_sha256": config_hash,
                    },
                    "module_results": [{"key": "temperature", "status": "ok"}],
                }

            compatible.write_text(json.dumps(payload("A" * 64)), encoding="utf-8")
            stale.write_text(json.dumps(payload("B" * 64)), encoding="utf-8")
            os.utime(compatible, (1, 1))
            os.utime(stale, (2, 2))
            self.assertEqual(find_latest_manifest(root), stale)
            self.assertEqual(
                find_latest_manifest(
                    root,
                    bridge_id="guanbing",
                    start_date="2026-06-01",
                    end_date="2026-06-30",
                    config_path=config,
                    config_sha256="A" * 64,
                    selected_modules=["temperature"],
                    successful_only=True,
                ),
                compatible,
            )


if __name__ == "__main__":
    unittest.main()
