from __future__ import annotations

import json
import tempfile
import unittest
from datetime import datetime
from pathlib import Path
from unittest.mock import MagicMock, patch

from workbench.models import file_sha256
from workbench.threshold_curve import (
    ThresholdCurveError,
    discover_threshold_curve_records,
    launch,
    load_current_threshold_curve,
    load_threshold_curve_preview,
    load_threshold_curve_reference,
    load_threshold_curve_record,
    load_result,
    prepare_threshold_curve_request,
    read_status,
    request_stop,
)
from workbench.threshold_preview import find_matching_threshold_preview, preview_query


def _write_curve_preview(
    path: Path,
    *,
    data_root: Path,
    bridge_id: str = "unit_bridge",
    config_sha256: str = "a" * 64,
    module_key: str = "acceleration",
    point_id: str = "A-1",
    request_id: str = "curve_unit",
) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(
            {
                "schema_version": 1,
                "artifact_type": "threshold_curve_preview",
                "request_type": "threshold_curve_generation",
                "request_id": request_id,
                "bridge_id": bridge_id,
                "data_root": str(data_root.resolve()),
                "config_sha256": config_sha256,
                "start_date": "2026-04-01",
                "end_date": "2026-04-30",
                "module_key": module_key,
                "point_id": point_id,
                "sensor_type": "acceleration",
                "curve_records": [
                    {
                        "module_key": module_key,
                        "point_id": point_id,
                        "sensor_type": "acceleration",
                        "times": ["2026-04-01T00:00:00", "2026-04-01T00:00:01"],
                        "values": [1.25, None],
                        "sample_count": 2,
                        "source_sample_count": 10,
                        "finite_sample_count": 8,
                    }
                ],
            },
            ensure_ascii=False,
        ),
        encoding="utf-8",
    )


def _write_curve_record(path: Path, *, data_root: Path, preview: Path) -> None:
    path.write_text(
        json.dumps(
            {
                "schema_version": 1,
                "artifact_type": "threshold_curve_record",
                "request_type": "threshold_curve_generation",
                "request_id": "curve_unit",
                "bridge_id": "unit_bridge",
                "data_root": str(data_root.resolve()),
                "config_sha256": "a" * 64,
                "start_date": "2026-04-01",
                "end_date": "2026-04-30",
                "module_key": "acceleration",
                "point_id": "A-1",
                "sensor_type": "acceleration",
                "preview_path": str(preview.resolve()),
                "preview_sha256": file_sha256(preview),
                "curve_record_count": 1,
                "sample_count": 2,
                "source_sample_count": 10,
                "finite_sample_count": 8,
                "created_at": "2026-07-18T12:00:00+08:00",
            },
            ensure_ascii=False,
        ),
        encoding="utf-8",
    )


class WorkbenchThresholdCurveTests(unittest.TestCase):
    def test_prepare_is_single_point_cache_first_and_has_own_stop_flag(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            data_root = root / "data"
            data_root.mkdir()
            config = root / "config.json"
            config.write_text("{}", encoding="utf-8")
            paths, payload = prepare_threshold_curve_request(
                bridge_id="unit_bridge",
                data_root=data_root,
                config_path=config,
                start_date="2026-04-01",
                end_date="2026-04-30",
                module_key="acceleration",
                point_id="A-1",
                now=datetime(2026, 7, 18, 12, 0, 0),
                request_id="curve_unit",
            )
            self.assertEqual(payload["request_type"], "threshold_curve_generation")
            self.assertEqual(payload["module_key"], "acceleration")
            self.assertEqual(payload["point_id"], "A-1")
            self.assertTrue(payload["prefer_mat_cache"])
            self.assertIsNone(payload["threshold_algorithm"])
            self.assertEqual(payload["stop_file"], str(paths.stop))
            self.assertNotIn("stop_path", payload)
            self.assertEqual(payload["result_path"], str(paths.result))
            self.assertEqual(payload["options"]["preview_sample_count"], 20_000)
            status = read_status(paths.status, expected_request_id="curve_unit")
            self.assertEqual(status["status"], "prepared")
            self.assertEqual(status["module_total"], 1)
            self.assertEqual(status["point_total"], 1)
            self.assertEqual(status["total_dates"], 30)
            self.assertEqual(status["progress_percent"], 0.0)

            stopped = request_stop(paths)
            self.assertEqual(stopped, paths.stop)
            stop_payload = json.loads(stopped.read_text(encoding="utf-8"))
            self.assertEqual(stop_payload["request_id"], "curve_unit")
            self.assertEqual(stop_payload["request_type"], "threshold_curve_generation")

            request_payload = json.loads(paths.request.read_text(encoding="utf-8"))
            request_payload["stop_file"] = str(root / "another_task" / "stop.flag")
            paths.request.write_text(json.dumps(request_payload), encoding="utf-8")
            other_stop = root / "another_task" / "stop.flag"
            other_stop.parent.mkdir()
            other_stop.write_text("keep", encoding="utf-8")
            with self.assertRaisesRegex(ThresholdCurveError, "不属于本次"):
                request_stop(paths)
            self.assertEqual(other_stop.read_text(encoding="utf-8"), "keep")

    def test_launch_uses_only_prepared_request_and_removes_only_own_stale_stop(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            project = root / "project"
            runner = project / "bin" / "BridgeAnalysisRunner" / "BridgeAnalysisRunner.exe"
            runner.parent.mkdir(parents=True)
            runner.write_bytes(b"runner")
            data_root = root / "data"
            data_root.mkdir()
            config = root / "config.json"
            config.write_text("{}", encoding="utf-8")
            paths, payload = prepare_threshold_curve_request(
                bridge_id="unit_bridge",
                data_root=data_root,
                config_path=config,
                start_date="2026-04-01",
                end_date="2026-04-30",
                module_key="acceleration",
                point_id="A-1",
                request_id="curve_launch",
            )
            paths.stop.write_text("stale own flag", encoding="utf-8")
            process = MagicMock()
            process.pid = 1234
            with patch(
                "workbench.threshold_curve.subprocess.Popen", return_value=process
            ) as popen:
                run = launch(project, paths, payload["config_sha256"])
            self.assertIs(run.process, process)
            self.assertEqual(run.request_id, "curve_launch")
            self.assertFalse(paths.stop.exists())
            self.assertEqual(popen.call_args.args[0], [str(runner.resolve()), str(paths.request)])
            self.assertEqual(popen.call_args.kwargs["stdin"], -3)

    def test_prepare_rejects_invalid_dates_and_missing_identity(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            config = root / "config.json"
            config.write_text("{}", encoding="utf-8")
            common = dict(
                bridge_id="unit",
                data_root=root,
                config_path=config,
                start_date="2026-04-30",
                end_date="2026-04-01",
                module_key="temperature",
                point_id="T-1",
            )
            with self.assertRaisesRegex(ThresholdCurveError, "不能晚于"):
                prepare_threshold_curve_request(**common)
            with self.assertRaisesRegex(ThresholdCurveError, "当前测点不能为空"):
                prepare_threshold_curve_request(
                    **{**common, "start_date": "2026-04-01", "point_id": ""}
                )
            config.write_text('{"bridge_id":"other"}', encoding="utf-8")
            with self.assertRaisesRegex(ThresholdCurveError, "bridge_id 不一致"):
                prepare_threshold_curve_request(
                    **{
                        **common,
                        "start_date": "2026-04-01",
                        "end_date": "2026-04-30",
                    }
                )

    def test_status_uses_only_canonical_progress_and_stop_file(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            status_path = Path(folder) / "status.json"
            status_path.write_text(
                json.dumps(
                    {
                        "request_type": "threshold_curve_generation",
                        "request_id": "curve",
                        "status": "running",
                        "progress_fraction": 0.375,
                        "progress_percent": 37.5,
                        "stop_file": "one/stop.flag",
                    }
                ),
                encoding="utf-8",
            )
            status = read_status(status_path, expected_request_id="curve")
            self.assertEqual(status["progress_fraction"], 0.375)
            self.assertEqual(status["stop_file"], "one/stop.flag")
            self.assertNotIn("stop_path", status)
            self.assertEqual(
                read_status(status_path, expected_request_id="other")["status"],
                "status_read_failed",
            )
            status_path.write_text(
                json.dumps(
                    {
                        "request_type": "threshold_curve_generation",
                        "request_id": "curve",
                        "status": "running",
                        "stop_path": "removed/legacy.flag",
                    }
                ),
                encoding="utf-8",
            )
            legacy = read_status(status_path, expected_request_id="curve")
            self.assertEqual(legacy["stop_file"], "")

    def test_new_preview_accepts_canonical_counts_and_strictly_binds_context(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            data_root = Path(folder)
            preview = data_root / "preview.json"
            _write_curve_preview(preview, data_root=data_root)
            expected = dict(
                expected_bridge_id="UNIT_BRIDGE",
                expected_data_root=data_root / ".",
                expected_start_date="2026-04-01",
                expected_end_date="2026-04-30",
                expected_config_sha256="a" * 64,
                expected_module_key="acceleration",
                expected_point_ids=("A_1", "A-1"),
                expected_request_id="curve_unit",
                expected_sha256=file_sha256(preview),
            )
            rows = load_threshold_curve_preview(preview, **expected)
            self.assertEqual(rows[("acceleration", "A-1")].values, (1.25, None))

            mismatches = (
                ("expected_bridge_id", "other", "桥梁编号"),
                ("expected_data_root", data_root / "other", "数据目录"),
                ("expected_start_date", "2026-04-02", "开始日期"),
                ("expected_config_sha256", "b" * 64, "配置版本"),
                ("expected_module_key", "temperature", "身份不一致"),
                ("expected_point_ids", ("OTHER",), "身份不一致"),
            )
            for field, value, message in mismatches:
                with self.subTest(field=field), self.assertRaisesRegex(
                    ThresholdCurveError, message
                ):
                    load_threshold_curve_preview(
                        preview, **{**expected, field: value}
                    )

    def test_preview_rejects_removed_preview_series_and_count_aliases(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            preview = root / "preview.json"
            _write_curve_preview(preview, data_root=root)
            payload = json.loads(preview.read_text(encoding="utf-8"))
            payload["preview_series"] = payload.pop("curve_records")
            row = payload["preview_series"][0]
            preview.write_text(json.dumps(payload), encoding="utf-8")
            with self.assertRaisesRegex(ThresholdCurveError, "curve_records"):
                load_threshold_curve_preview(
                    preview,
                    expected_bridge_id="unit_bridge",
                    expected_data_root=root,
                    expected_start_date="2026-04-01",
                    expected_end_date="2026-04-30",
                    expected_config_sha256="a" * 64,
                    expected_module_key="acceleration",
                    expected_point_ids=("A-1",),
                )

            payload["curve_records"] = payload.pop("preview_series")
            row = payload["curve_records"][0]
            row["source_count"] = row.pop("source_sample_count")
            row["finite_count"] = row.pop("finite_sample_count")
            preview.write_text(json.dumps(payload), encoding="utf-8")
            with self.assertRaisesRegex(ThresholdCurveError, "source_sample_count"):
                load_threshold_curve_preview(
                    preview,
                    expected_bridge_id="unit_bridge",
                    expected_data_root=root,
                    expected_start_date="2026-04-01",
                    expected_end_date="2026-04-30",
                    expected_config_sha256="a" * 64,
                    expected_module_key="acceleration",
                    expected_point_ids=("A-1",),
                )

    def test_record_hash_closes_and_history_metadata_hides_raw_json_details(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            task = root / "run_logs" / "workbench" / "curve_unit"
            preview = task / "threshold_curve_preview.json"
            record = task / "threshold_curve_record.json"
            _write_curve_preview(preview, data_root=root)
            _write_curve_record(record, data_root=root, preview=preview)
            metadata = load_threshold_curve_record(record)
            self.assertEqual(metadata.bridge_id, "unit_bridge")
            self.assertEqual(metadata.date_label, "2026-04-01 至 2026-04-30")
            self.assertEqual(metadata.point_id, "A-1")
            self.assertEqual(metadata.sample_count, 2)
            self.assertEqual(metadata.source_sample_count, 10)
            self.assertEqual(metadata.finite_sample_count, 8)
            reference = load_threshold_curve_reference(record)
            self.assertIn(("acceleration", "A-1"), reference)
            current = load_current_threshold_curve(
                record,
                expected_bridge_id="unit_bridge",
                expected_data_root=root,
                expected_start_date="2026-04-01",
                expected_end_date="2026-04-30",
                expected_config_sha256="a" * 64,
                expected_module_key="acceleration",
                expected_point_ids=("A-1",),
            )
            self.assertIn(("acceleration", "A-1"), current)
            discovered = discover_threshold_curve_records(root)
            self.assertEqual(len(discovered), 1)
            self.assertEqual(discovered[0].record_path, record.resolve())

            preview.write_text(preview.read_text(encoding="utf-8") + "\n", encoding="utf-8")
            with self.assertRaisesRegex(ThresholdCurveError, "已变化"):
                load_threshold_curve_record(record)
            self.assertEqual(discover_threshold_curve_records(root), ())

    def test_corrupt_new_record_cannot_be_bypassed_by_neighbor_preview(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            task = root / "run_logs" / "workbench" / "curve_unit"
            preview = task / "threshold_curve_preview.json"
            record = task / "threshold_curve_record.json"
            _write_curve_preview(preview, data_root=root)
            _write_curve_record(record, data_root=root, preview=preview)
            payload = json.loads(record.read_text(encoding="utf-8"))
            payload["preview_sha256"] = "0" * 64
            record.write_text(json.dumps(payload), encoding="utf-8")
            match = find_matching_threshold_preview(
                preview_query(
                    bridge_id="unit_bridge",
                    data_root=root,
                    start_date="2026-04-01",
                    end_date="2026-04-30",
                    config_sha256="a" * 64,
                    module_key="acceleration",
                    point_ids=("A-1",),
                )
            )
            self.assertIsNone(match.path)
            self.assertEqual(match.checked_count, 1)

    def test_result_closes_result_record_and_preview_identity(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            task = root / "run_logs" / "workbench" / "curve_unit"
            preview = task / "threshold_curve_preview.json"
            record = task / "threshold_curve_record.json"
            result = task / "threshold_curve_result.json"
            _write_curve_preview(preview, data_root=root)
            _write_curve_record(record, data_root=root, preview=preview)
            result.write_text(
                json.dumps(
                    {
                        "schema_version": 1,
                        "artifact_type": "threshold_curve_generation_result",
                        "request_type": "threshold_curve_generation",
                        "request_id": "curve_unit",
                        "bridge_id": "unit_bridge",
                        "data_root": str(root.resolve()),
                        "config_sha256": "a" * 64,
                        "start_date": "2026-04-01",
                        "end_date": "2026-04-30",
                        "module_key": "acceleration",
                        "point_id": "A-1",
                        "sensor_type": "acceleration",
                        "record_path": str(record.resolve()),
                        "record_sha256": file_sha256(record),
                        "preview_path": str(preview.resolve()),
                        "preview_sha256": file_sha256(preview),
                        "curve_record_count": 1,
                        "sample_count": 2,
                        "source_sample_count": 10,
                        "finite_sample_count": 8,
                    }
                ),
                encoding="utf-8",
            )
            loaded = load_result(
                result,
                expected_request_id="curve_unit",
                expected_config_sha256="A" * 64,
            )
            self.assertEqual(loaded["record_metadata"].point_id, "A-1")
            record.write_text(record.read_text(encoding="utf-8") + "\n", encoding="utf-8")
            with self.assertRaisesRegex(ThresholdCurveError, "历史记录.*已变化"):
                load_result(result)

    def test_new_record_is_preferred_and_beta_auto_preview_is_ignored(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            task = root / "run_logs" / "workbench" / "curve_unit"
            preview = task / "threshold_curve_preview.json"
            record = task / "threshold_curve_record.json"
            _write_curve_preview(preview, data_root=root)
            _write_curve_record(record, data_root=root, preview=preview)

            legacy = root / "run_logs" / "workbench" / "legacy" / "auto_threshold_preview.json"
            legacy.parent.mkdir(parents=True)
            legacy.write_text(
                json.dumps(
                    {
                        "schema_version": 1,
                        "artifact_type": "auto_threshold_preview",
                        "request_type": "auto_threshold_proposal",
                        "request_id": "legacy",
                        "bridge_id": "unit_bridge",
                        "data_root": str(root.resolve()),
                        "config_sha256": "a" * 64,
                        "start_date": "2026-04-01",
                        "end_date": "2026-04-30",
                        "curve_records": [
                            {
                                "module_key": "acceleration",
                                "point_id": "A-1",
                                "sensor_type": "acceleration",
                                "times": ["2026-04-01T00:00:00"],
                                "values": [99.0],
                                "sample_count": 1,
                                "source_sample_count": 1,
                                "finite_sample_count": 1,
                            }
                        ],
                    }
                ),
                encoding="utf-8",
            )
            legacy.touch()
            match = find_matching_threshold_preview(
                preview_query(
                    bridge_id="unit_bridge",
                    data_root=root,
                    start_date="2026-04-01",
                    end_date="2026-04-30",
                    config_sha256="a" * 64,
                    module_key="acceleration",
                    point_ids=("A-1",),
                )
            )
            self.assertEqual(match.path, preview.resolve())
            self.assertEqual(match.source_kind, "threshold_curve_record")
            self.assertIn("独立曲线记录", match.message)

    def test_beta_auto_threshold_preview_is_rejected_and_not_discovered(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            legacy = root / "run_logs" / "legacy" / "auto_threshold_preview.json"
            legacy.parent.mkdir(parents=True)
            legacy.write_text(
                json.dumps(
                    {
                        "schema_version": 1,
                        "artifact_type": "auto_threshold_preview",
                        "request_type": "auto_threshold_proposal",
                        "request_id": "legacy",
                        "bridge_id": "unit_bridge",
                        "data_root": str(root.resolve()),
                        "config_sha256": "a" * 64,
                        "start_date": "2026-04-01",
                        "end_date": "2026-04-30",
                        "curve_records": [
                            {
                                "module_key": "temperature",
                                "point_id": "T-1",
                                "sensor_type": "temperature",
                                "times": ["2026-04-01T00:00:00"],
                                "values": [20.0],
                                "sample_count": 1,
                                "source_sample_count": 1,
                                "finite_sample_count": 1,
                            }
                        ],
                    }
                ),
                encoding="utf-8",
            )
            with self.assertRaisesRegex(ThresholdCurveError, "新版独立曲线"):
                load_current_threshold_curve(
                    legacy,
                    expected_bridge_id="unit_bridge",
                    expected_data_root=root,
                    expected_start_date="2026-04-01",
                    expected_end_date="2026-04-30",
                    expected_config_sha256="a" * 64,
                    expected_module_key="temperature",
                    expected_point_ids=("T-1",),
                )
            self.assertEqual(discover_threshold_curve_records(root), ())
            match = find_matching_threshold_preview(
                preview_query(
                    bridge_id="unit_bridge",
                    data_root=root,
                    start_date="2026-04-01",
                    end_date="2026-04-30",
                    config_sha256="a" * 64,
                    module_key="temperature",
                    point_ids=("T-1",),
                )
            )
            self.assertIsNone(match.path)
            self.assertEqual(match.checked_count, 0)


if __name__ == "__main__":
    unittest.main()
