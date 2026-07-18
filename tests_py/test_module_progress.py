from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from workbench.analysis import read_analysis_status
from workbench.models import JobContext
from workbench.module_progress import normalize_module_progress
from workbench.modules import options_for_modules


class ModuleProgressNormalizationTests(unittest.TestCase):
    def test_v2_runtime_contract_exposes_current_module_detail(self) -> None:
        progress = normalize_module_progress(
            {
                "progress_schema_version": 2,
                "status": "running",
                "stage": "loading_daily_cache",
                "module_index": 2,
                "current_module_key": "wind",
                "current_point_id": "W2",
                "current_date": "2026-04-08",
                "processed_dates": 7,
                "total_dates": 91,
                "elapsed_seconds": 12.5,
                "module_steps": [
                    {
                        "key": "temperature",
                        "label": "温度分析",
                        "index": 1,
                        "status": "ok",
                        "elapsed_sec": 2.0,
                    },
                    {
                        "key": "wind",
                        "label": "风速风向分析",
                        "index": 2,
                        "status": "running",
                    },
                ],
            }
        )

        self.assertEqual(progress.authority, "runtime")
        self.assertEqual(progress.completed_count, 1)
        self.assertEqual(progress.total_count, 2)
        self.assertEqual(progress.progress_fraction, 0.5)
        self.assertIsNotNone(progress.current_step)
        assert progress.current_step is not None
        self.assertEqual(progress.current_step.key, "wind")
        self.assertEqual(progress.current_step.current_point_id, "W2")
        self.assertEqual(progress.current_step.current_date, "2026-04-08")
        self.assertEqual(progress.current_step.processed_dates, 7)
        self.assertEqual(progress.current_step.total_dates, 91)
        self.assertEqual(progress.current_step.elapsed_seconds, 12.5)
        self.assertEqual(progress.current_step.stage, "loading_daily_cache")
        self.assertEqual(progress.summary_text, "已完成1/2；当前2/2：风速风向分析")

    def test_legacy_completed_scalars_do_not_claim_module_success(self) -> None:
        progress = normalize_module_progress(
            {
                "status": "completed",
                "completed_modules": 2,
                "module_total": 2,
                "progress_fraction": 1.0,
                "current_module_key": "wind",
                "current_module_label": "风速风向分析",
                "current_module_status": "ok",
            },
            selected_modules=["temperature", "wind"],
        )

        self.assertEqual(progress.authority, "legacy_status")
        self.assertEqual([step.status for step in progress.steps], ["pending", "pending"])
        self.assertEqual(progress.completed_count, 0)
        self.assertEqual(progress.progress_fraction, 0.0)
        self.assertIsNone(progress.current_step)

    def test_legacy_running_status_keeps_only_explicit_current_module(self) -> None:
        progress = normalize_module_progress(
            {
                "status": "running",
                "current_module_key": "wind",
                "current_module_label": "风速风向分析",
                "completed_modules": 8,
                "progress_fraction": 0.8,
                "current_point_id": "W1",
            },
            selected_modules=["temperature", "wind", "deflection"],
        )

        self.assertEqual(
            [step.status for step in progress.steps],
            ["pending", "running", "pending"],
        )
        self.assertEqual(progress.completed_count, 0)
        self.assertEqual(progress.current_step.current_point_id, "W1")

    def test_terminal_manifest_is_authoritative_for_all_module_statuses(self) -> None:
        runtime = {
            "progress_schema_version": 2,
            "status": "completed",
            "current_module_key": "unknown",
            "module_steps": [
                {"key": "ok", "status": "running"},
                {"key": "bad", "status": "completed"},
                {"key": "gap", "status": "completed"},
                {"key": "halt", "status": "completed"},
                {"key": "unknown", "status": "completed"},
            ],
        }
        manifest = {
            "status": "failed",
            "module_results": [
                {"key": "ok", "label": "成功项", "status": "success"},
                {"key": "bad", "label": "失败项", "status": "failure"},
                {
                    "key": "gap",
                    "label": "无数据项",
                    "status": "no_data",
                    "message": "设备断采",
                },
                {"key": "halt", "label": "停止项", "status": "stopped"},
                {"key": "unknown", "label": "未知项", "status": "future_state"},
            ],
        }

        progress = normalize_module_progress(runtime, manifest)

        self.assertEqual(progress.authority, "analysis_manifest")
        self.assertEqual(
            [step.status for step in progress.steps],
            ["completed", "failed", "skipped", "stopped", "failed"],
        )
        self.assertEqual(progress.completed_count, 5)
        self.assertEqual(progress.progress_fraction, 1.0)
        self.assertIsNone(progress.current_step)
        self.assertEqual(progress.steps[2].message, "设备断采")

    def test_terminal_manifest_marks_planned_but_unrecorded_module_failed(self) -> None:
        progress = normalize_module_progress(
            {
                "progress_schema_version": 2,
                "status": "completed",
                "module_steps": [
                    {"key": "temperature", "status": "completed"},
                    {"key": "wind", "status": "completed"},
                ],
            },
            {"status": "ok", "module_results": [{"key": "temperature", "status": "ok"}]},
        )

        self.assertEqual(progress.steps[0].status, "completed")
        self.assertEqual(progress.steps[1].status, "failed")
        self.assertEqual(progress.steps[1].stage, "manifest_reconciliation")
        self.assertIn("最终分析清单缺少", progress.steps[1].message)
        self.assertIn("失败1", progress.summary_text)
        self.assertNotIn("全部通过", progress.summary_text)

    def test_explicit_empty_terminal_module_results_are_authoritative(self) -> None:
        progress = normalize_module_progress(
            {
                "status": "completed",
                "completed_modules": 2,
                "progress_fraction": 1.0,
            },
            {"status": "failed", "module_results": []},
            selected_modules=["temperature", "wind"],
        )

        self.assertEqual(progress.authority, "analysis_manifest")
        self.assertEqual([step.status for step in progress.steps], ["failed", "failed"])
        self.assertTrue(
            all("最终分析清单缺少" in step.message for step in progress.steps)
        )

    def test_matlab_single_struct_json_shape_is_supported(self) -> None:
        progress = normalize_module_progress(
            {
                "progress_schema_version": 2,
                "progress_authority": "analysis_manifest",
                "status": "completed",
                "module_steps": {
                    "key": "wind",
                    "label": "风速风向分析",
                    "index": 1,
                    "status": "completed",
                    "processed_dates": 91,
                    "total_dates": 91,
                },
            },
            {
                "status": "ok",
                "module_results": {
                    "key": "wind",
                    "label": "风速风向分析",
                    "status": "ok",
                },
            },
        )

        self.assertEqual(progress.authority, "analysis_manifest")
        self.assertEqual(len(progress.steps), 1)
        self.assertEqual(progress.steps[0].status, "completed")
        self.assertEqual(progress.steps[0].processed_dates, 91)
        self.assertEqual(progress.progress_fraction, 1.0)

    def test_v2_date_fraction_does_not_masquerade_as_module_progress(self) -> None:
        with_days = normalize_module_progress(
            {
                "progress_schema_version": 2,
                "status": "running",
                "current_module_key": "temperature",
                "module_steps": [
                    {
                        "key": "temperature",
                        "status": "running",
                        "processed_dates": 1,
                        "total_dates": 2,
                    },
                    {"key": "wind", "status": "pending"},
                ],
            }
        )
        without_days = normalize_module_progress(
            {
                "progress_schema_version": 2,
                "status": "running",
                "progress_fraction": 0.9,
                "current_module_key": "temperature",
                "module_steps": [
                    {"key": "temperature", "status": "running"},
                    {"key": "wind", "status": "pending"},
                ],
            }
        )

        self.assertEqual(with_days.progress_fraction, 0.0)
        self.assertEqual(without_days.progress_fraction, 0.0)


class AnalysisStatusProgressReconciliationTests(unittest.TestCase):
    def test_read_analysis_status_overlays_terminal_manifest_results(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            config = root / "config.json"
            config.write_text(
                '{"plot_common":{"gap_mode":"connect"}}', encoding="utf-8"
            )
            data_root = root / "data"
            data_root.mkdir()
            context = JobContext.create(
                project_root=root,
                bridge_id="unit",
                bridge_name="测试桥梁",
                data_root=data_root,
                start_date="2026-04-01",
                end_date="2026-06-30",
                config_path=config,
                selected_modules=["temperature", "wind"],
                options=options_for_modules(["temperature", "wind"]),
                job_id="progress_reconcile",
            )
            manifest_path = data_root / "run_logs" / "analysis_manifest_unit.json"
            manifest_path.parent.mkdir(parents=True, exist_ok=True)
            manifest_path.write_text(
                json.dumps(
                    {
                        "status": "failed",
                        "module_results": [
                            {"key": "temperature", "label": "温度分析", "status": "ok"},
                            {
                                "key": "wind",
                                "label": "风速风向分析",
                                "status": "fail",
                                "message": "源文件读取失败",
                            },
                        ],
                    },
                    ensure_ascii=False,
                ),
                encoding="utf-8",
            )
            status_path = Path(context.analysis.status_path)
            status_path.parent.mkdir(parents=True, exist_ok=True)
            status_path.write_text(
                json.dumps(
                    {
                        "status": "failed",
                        "manifest_path": str(manifest_path),
                        "completed_modules": 2,
                        "progress_fraction": 1.0,
                    }
                ),
                encoding="utf-8",
            )

            status = read_analysis_status(context)

            self.assertEqual(status["status"], "failed")
            self.assertEqual(status["progress_schema_version"], 2)
            self.assertEqual(status["progress_authority"], "analysis_manifest")
            self.assertEqual(
                [step["status"] for step in status["module_steps"]],
                ["completed", "failed"],
            )
            self.assertEqual(status["completed_modules"], 2)
            self.assertEqual(status["progress_fraction"], 1.0)


if __name__ == "__main__":
    unittest.main()
