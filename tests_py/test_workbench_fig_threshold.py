from __future__ import annotations

import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import ANY, patch

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

from workbench.fig_threshold import (
    FigThresholdCancelled,
    FigThresholdError,
    REQUEST_TYPE,
    _load_and_validate_outcome,
    _spawn_runner,
    _wait_for_process_with_qt,
    prepare_fig_threshold_request,
    resolve_runner,
    run_fig_threshold_interaction,
)
from workbench.models import file_sha256

try:
    from PySide6.QtWidgets import QApplication
except ImportError:  # pragma: no cover
    QApplication = None


def _write_json(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")


class _FakeProcess:
    def __init__(self, return_code: int = 0) -> None:
        self.return_code = return_code

    def poll(self) -> int:
        return self.return_code

    def wait(self) -> int:
        return self.return_code


class _EventuallyCompleteProcess:
    def __init__(self, pending_polls: int = 3) -> None:
        self.pending_polls = pending_polls
        self.poll_count = 0

    def poll(self) -> int | None:
        self.poll_count += 1
        if self.poll_count <= self.pending_polls:
            return None
        return 0

    def wait(self) -> int:
        return 0


class _CancellableProcess:
    def __init__(self) -> None:
        self.return_code: int | None = None
        self.terminate_count = 0
        self.kill_count = 0

    def poll(self) -> int | None:
        return self.return_code

    def wait(self) -> int:
        return int(self.return_code or 0)

    def terminate(self) -> None:
        self.terminate_count += 1
        self.return_code = 1

    def kill(self) -> None:
        self.kill_count += 1
        self.return_code = 1


class _FakeWaitDialog:
    def __init__(self) -> None:
        self.shown = False
        self.accepted = False
        self.deleted = False

    def show(self) -> None:
        self.shown = True

    def accept(self) -> None:
        self.accepted = True

    def deleteLater(self) -> None:
        self.deleted = True


class FigThresholdServiceTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.project = self.root / "project"
        self.project.mkdir()
        self.runner = (
            self.project / "bin" / "BridgeAnalysisRunner" / "BridgeAnalysisRunner.exe"
        )
        self.runner.parent.mkdir(parents=True)
        self.runner.write_bytes(b"runner")
        self.fig = self.root / "reference.fig"
        self.fig.write_bytes(b"MATLAB FIG fixture")

    def tearDown(self) -> None:
        self.temp.cleanup()

    def _prepared(self, operation: str = "band"):
        return prepare_fig_threshold_request(
            self.project,
            self.fig,
            operation,
            "acceleration",
            "A-1",
            request_id="fig_unit",
            run_root=self.root / "run",
        )

    @staticmethod
    def _status(request: dict, state: str = "completed", **extra) -> dict:
        payload = {
            "status": state,
            "request_type": REQUEST_TYPE,
            "request_id": request["request_id"],
        }
        if state in {"completed", "ok"}:
            payload.update(
                {
                    "operation": request["operation"],
                    "result_path": request["result_path"],
                    "result_status": "ok",
                }
            )
        payload.update(extra)
        return payload

    def _result(self, request: dict, *, candidate: dict | None = None, **extra) -> dict:
        operation = request["operation"]
        if candidate is None:
            if operation == "band":
                candidate = {
                    "lower": -2.5,
                    "upper": 7.5,
                    "t_range_start": "2026-05-01 00:00:00",
                    "t_range_end": "2026-05-31 23:59:59",
                }
            else:
                candidate = {
                    "side": "lower" if operation == "box_lower" else "upper",
                    "value": -1.25 if operation == "box_lower" else 8.75,
                    "selected_sample_count": 17,
                    "selection_start": "2026-05-02 00:00:00",
                    "selection_end": "2026-05-03 00:00:00",
                }
        return {
            "schema_version": 1,
            "artifact_type": "fig_threshold_result",
            "request_type": REQUEST_TYPE,
            "request_id": request["request_id"],
            "status": "ok",
            "operation": operation,
            "target_module": request["target_module"],
            "target_point": request["target_point"],
            "source_fig": {
                "path": request["fig_path"],
                "sha256": request["fig_sha256"],
                "size": request["fig_size_bytes"],
                "mtime": "2026-07-17T00:00:00",
            },
            "source_curve": {
                "axis_title": "加速度时程",
                "curve_label": "A-1",
                "sample_count": 1234,
            },
            "candidate": candidate,
            **extra,
        }

    def test_prepare_request_uses_flat_matlab_contract_and_source_binding(self) -> None:
        paths, request = self._prepared()
        self.assertEqual(request["schema_version"], 1)
        self.assertEqual(request["request_type"], REQUEST_TYPE)
        self.assertEqual(request["request_id"], "fig_unit")
        self.assertEqual(request["operation"], "band")
        self.assertEqual(request["fig_path"], str(self.fig.resolve()))
        self.assertEqual(request["fig_sha256"], file_sha256(self.fig))
        self.assertEqual(request["fig_size_bytes"], self.fig.stat().st_size)
        self.assertEqual(request["target_module"], "acceleration")
        self.assertEqual(request["target_point"], "A-1")
        self.assertNotIn("target", request)
        self.assertNotIn("source_fig", request)
        self.assertEqual(json.loads(paths.request.read_text(encoding="utf-8")), request)
        status = json.loads(paths.status.read_text(encoding="utf-8"))
        self.assertEqual(status["status"], "prepared")
        self.assertEqual(status["fig_sha256"], request["fig_sha256"])

    def test_prepare_rejects_raster_missing_fig_invalid_operation_and_empty_target(self) -> None:
        raster = self.root / "reference.jpg"
        raster.write_bytes(b"jpg")
        with self.assertRaisesRegex(FigThresholdError, r"\.fig"):
            prepare_fig_threshold_request(
                self.project, raster, "band", "acceleration", "A-1"
            )
        with self.assertRaisesRegex(FigThresholdError, "不存在"):
            prepare_fig_threshold_request(
                self.project, self.root / "missing.fig", "band", "acceleration", "A-1"
            )
        with self.assertRaisesRegex(FigThresholdError, "不支持"):
            prepare_fig_threshold_request(
                self.project, self.fig, "lower_box", "acceleration", "A-1"
            )
        with self.assertRaisesRegex(FigThresholdError, "分析类型"):
            prepare_fig_threshold_request(self.project, self.fig, "band", " ", "A-1")
        with self.assertRaisesRegex(FigThresholdError, "目标测点"):
            prepare_fig_threshold_request(
                self.project, self.fig, "box_lower", "acceleration", " "
            )

    def test_resolve_runner_supports_source_and_frozen_project_roots(self) -> None:
        self.assertEqual(resolve_runner(self.project), self.runner.resolve())
        frozen = self.root / "frozen"
        frozen_runner = frozen / "dist" / "BridgeAnalysisRunner" / "BridgeAnalysisRunner"
        frozen_runner.parent.mkdir(parents=True)
        frozen_runner.write_bytes(b"runner")
        self.assertEqual(resolve_runner(frozen), frozen_runner.resolve())
        with self.assertRaisesRegex(FigThresholdError, "BridgeAnalysisRunner"):
            resolve_runner(self.root / "empty")

    def test_spawn_runner_hides_console_and_binds_request_path(self) -> None:
        paths, _request = self._prepared()
        fake = _FakeProcess()
        with patch("workbench.fig_threshold.subprocess.Popen", return_value=fake) as popen:
            actual = _spawn_runner(self.runner, paths)
        self.assertIs(actual, fake)
        args, kwargs = popen.call_args
        self.assertEqual(args[0], [str(self.runner), str(paths.request)])
        self.assertEqual(kwargs["stdin"], -3)  # subprocess.DEVNULL
        if os.name == "nt":
            import subprocess

            self.assertEqual(
                kwargs["creationflags"],
                subprocess.CREATE_NO_WINDOW | subprocess.CREATE_NEW_PROCESS_GROUP,
            )

    def test_loads_strict_band_result(self) -> None:
        paths, request = self._prepared("band")
        _write_json(paths.status, self._status(request))
        _write_json(paths.result, self._result(request))
        result = _load_and_validate_outcome(paths, request, return_code=0)
        self.assertEqual(result["candidate"]["lower"], -2.5)
        self.assertEqual(result["candidate"]["upper"], 7.5)
        self.assertEqual(result["source_curve"]["sample_count"], 1234)

    def test_loads_strict_box_results(self) -> None:
        for operation, side in (("box_lower", "lower"), ("box_upper", "upper")):
            with self.subTest(operation=operation):
                run_root = self.root / operation
                paths, request = prepare_fig_threshold_request(
                    self.project,
                    self.fig,
                    operation,
                    "acceleration",
                    "A-1",
                    request_id=operation,
                    run_root=run_root,
                )
                _write_json(paths.status, self._status(request))
                _write_json(paths.result, self._result(request))
                result = _load_and_validate_outcome(paths, request, return_code=0)
                self.assertEqual(result["candidate"]["side"], side)
                self.assertEqual(result["candidate"]["selected_sample_count"], 17)

    def test_cancelled_is_distinct_from_failure(self) -> None:
        paths, request = self._prepared()
        _write_json(paths.status, self._status(request, "cancelled", message="用户取消"))
        with self.assertRaisesRegex(FigThresholdCancelled, "用户取消"):
            _load_and_validate_outcome(paths, request, return_code=0)

        _write_json(
            paths.status,
            self._status(request, "completed", result_status="cancelled"),
        )
        _write_json(paths.result, self._result(request, status="cancelled"))
        with self.assertRaises(FigThresholdCancelled):
            _load_and_validate_outcome(paths, request, return_code=0)

    def test_failed_status_and_nonzero_exit_include_background_evidence(self) -> None:
        paths, request = self._prepared()
        paths.stderr.write_text("MATLAB failure detail", encoding="utf-8")
        _write_json(paths.status, self._status(request, "failed", message="FIG 读取失败"))
        with self.assertRaisesRegex(FigThresholdError, "MATLAB failure detail"):
            _load_and_validate_outcome(paths, request, return_code=1)

        _write_json(paths.status, self._status(request, "completed"))
        _write_json(paths.result, self._result(request))
        with self.assertRaisesRegex(FigThresholdError, "代码 7"):
            _load_and_validate_outcome(paths, request, return_code=7)

    def test_rejects_identity_source_hash_and_source_mutation(self) -> None:
        paths, request = self._prepared()
        _write_json(paths.status, self._status(request))
        wrong = self._result(request)
        wrong["target_point"] = "OTHER"
        _write_json(paths.result, wrong)
        with self.assertRaisesRegex(FigThresholdError, "目标测点"):
            _load_and_validate_outcome(paths, request, return_code=0)

        wrong = self._result(request)
        wrong["source_fig"]["sha256"] = "0" * 64
        _write_json(paths.result, wrong)
        with self.assertRaisesRegex(FigThresholdError, "SHA256"):
            _load_and_validate_outcome(paths, request, return_code=0)

        wrong = self._result(request)
        wrong["artifact_type"] = "other"
        _write_json(paths.result, wrong)
        with self.assertRaisesRegex(FigThresholdError, "artifact_type"):
            _load_and_validate_outcome(paths, request, return_code=0)

        wrong = self._result(request)
        wrong["source_fig"]["size"] += 1
        _write_json(paths.result, wrong)
        with self.assertRaisesRegex(FigThresholdError, "文件大小"):
            _load_and_validate_outcome(paths, request, return_code=0)

        _write_json(paths.result, self._result(request))
        self.fig.write_bytes(b"source changed after request")
        with self.assertRaisesRegex(FigThresholdError, "发生变化"):
            _load_and_validate_outcome(paths, request, return_code=0)

    def test_rejects_invalid_band_and_box_candidates(self) -> None:
        paths, request = self._prepared("band")
        _write_json(paths.status, self._status(request))
        _write_json(
            paths.result,
            self._result(
                request,
                candidate={
                    "lower": 2,
                    "upper": 2,
                    "t_range_start": "",
                    "t_range_end": "",
                },
            ),
        )
        with self.assertRaisesRegex(FigThresholdError, "下限小于上限"):
            _load_and_validate_outcome(paths, request, return_code=0)

        box_paths, box_request = prepare_fig_threshold_request(
            self.project,
            self.fig,
            "box_lower",
            "acceleration",
            "A-1",
            request_id="box_invalid",
            run_root=self.root / "box_invalid",
        )
        _write_json(box_paths.status, self._status(box_request))
        _write_json(
            box_paths.result,
            self._result(
                box_request,
                candidate={
                    "side": "upper",
                    "value": 1,
                    "selected_sample_count": 0,
                    "selection_start": "",
                    "selection_end": "",
                },
            ),
        )
        with self.assertRaisesRegex(FigThresholdError, "方向"):
            _load_and_validate_outcome(box_paths, box_request, return_code=0)

    def test_status_result_binding_is_fail_closed(self) -> None:
        paths, request = self._prepared()
        _write_json(paths.result, self._result(request))
        wrong_operation = self._status(request)
        wrong_operation["operation"] = "box_lower"
        _write_json(paths.status, wrong_operation)
        with self.assertRaisesRegex(FigThresholdError, "操作类型"):
            _load_and_validate_outcome(paths, request, return_code=0)

        wrong_path = self._status(request)
        wrong_path["result_path"] = str(self.root / "other.json")
        _write_json(paths.status, wrong_path)
        with self.assertRaisesRegex(FigThresholdError, "结果路径"):
            _load_and_validate_outcome(paths, request, return_code=0)

        wrong_status = self._status(request, result_status="cancelled")
        _write_json(paths.status, wrong_status)
        with self.assertRaisesRegex(FigThresholdError, "记录的状态不一致"):
            _load_and_validate_outcome(paths, request, return_code=0)

    def test_public_api_returns_validated_payload_for_dialog_candidate(self) -> None:
        fake_process = _FakeProcess()

        def spawn(_runner: Path, paths) -> _FakeProcess:
            request = json.loads(paths.request.read_text(encoding="utf-8"))
            _write_json(paths.status, self._status(request))
            _write_json(paths.result, self._result(request))
            return fake_process

        with (
            patch("workbench.fig_threshold._application_data_root", return_value=self.root / "runs"),
            patch("workbench.fig_threshold._spawn_runner", side_effect=spawn),
            patch("workbench.fig_threshold._wait_for_process_with_qt", return_value=0) as wait,
        ):
            result = run_fig_threshold_interaction(
                self.project, self.fig, "band", "acceleration", "A-1", parent=object()
            )
        self.assertEqual(result["candidate"]["lower"], -2.5)
        wait.assert_called_once_with(fake_process, parent=ANY)

    def test_public_api_persists_terminal_status_when_operator_cancels(self) -> None:
        fake_process = _FakeProcess()
        captured_paths = []

        def spawn(_runner: Path, paths) -> _FakeProcess:
            request = json.loads(paths.request.read_text(encoding="utf-8"))
            _write_json(paths.status, self._status(request, "running"))
            captured_paths.append(paths)
            return fake_process

        with (
            patch("workbench.fig_threshold._application_data_root", return_value=self.root / "runs"),
            patch("workbench.fig_threshold._spawn_runner", side_effect=spawn),
            patch(
                "workbench.fig_threshold._wait_for_process_with_qt",
                side_effect=FigThresholdCancelled("操作员取消"),
            ),
        ):
            with self.assertRaisesRegex(FigThresholdCancelled, "操作员取消"):
                run_fig_threshold_interaction(
                    self.project,
                    self.fig,
                    "band",
                    "acceleration",
                    "A-1",
                    parent=object(),
                )

        status = json.loads(captured_paths[0].status.read_text(encoding="utf-8"))
        request = json.loads(captured_paths[0].request.read_text(encoding="utf-8"))
        self.assertEqual(status["status"], "cancelled")
        self.assertEqual(status["runner_status_before_cancel"], "running")
        self.assertEqual(status["request_id"], request["request_id"])
        self.assertEqual(Path(status["request_path"]), captured_paths[0].request)
        self.assertEqual(Path(status["result_path"]), captured_paths[0].result)
        self.assertFalse(captured_paths[0].result.exists())

    @unittest.skipIf(QApplication is None, "PySide6 is not installed")
    def test_nested_qt_event_loop_waits_without_blocking_ui(self) -> None:
        app = QApplication.instance() or QApplication([])
        process = _EventuallyCompleteProcess(pending_polls=4)
        return_code = _wait_for_process_with_qt(process, poll_interval_ms=10)
        app.processEvents()
        self.assertEqual(return_code, 0)
        self.assertGreater(process.poll_count, 4)

    @unittest.skipIf(QApplication is None, "PySide6 is not installed")
    def test_wait_dialog_can_stop_only_the_spawned_fig_process(self) -> None:
        QApplication.instance() or QApplication([])
        process = _CancellableProcess()
        dialog = _FakeWaitDialog()

        def create_dialog(_parent, on_cancel):
            on_cancel()
            return dialog

        with patch(
            "workbench.fig_threshold._create_fig_wait_dialog",
            side_effect=create_dialog,
        ):
            with self.assertRaisesRegex(FigThresholdCancelled, "已停止"):
                _wait_for_process_with_qt(
                    process,
                    parent=object(),
                    poll_interval_ms=10,
                )
        self.assertEqual(process.terminate_count, 1)
        self.assertEqual(process.kill_count, 0)
        self.assertTrue(dialog.shown)
        self.assertTrue(dialog.accepted)
        self.assertTrue(dialog.deleted)


if __name__ == "__main__":
    unittest.main()
