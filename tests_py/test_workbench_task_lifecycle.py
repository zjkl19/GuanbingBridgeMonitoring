from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

from workbench.analysis import (
    AnalysisLauncher,
    Executor,
    ExecutorResolver,
    LaunchResult,
    persist_analysis_state,
    read_analysis_status,
)
from workbench.models import JobContext, file_sha256
from workbench.modules import options_for_modules
from workbench.process_utils import (
    assert_no_live_process_lease,
    atomic_write_json,
    capture_process_identity,
    capture_spawned_process_identity,
    exclusive_file_lock,
    pid_running,
    process_identity,
    process_identity_state,
    process_matches,
    publish_process_lease,
    terminate_exact_process,
)
from workbench.report_task import (
    ReportLaunchResult,
    _wait_for_process_exit,
    launch_report_job,
    persist_report_state,
    read_report_status,
    terminate_report_job,
)

try:
    from PySide6.QtWidgets import QApplication

    from workbench.main_window import WorkbenchWindow
except ImportError:  # pragma: no cover - dependency gate
    QApplication = None
    WorkbenchWindow = None


class _FakeProcess:
    pid = 31415

    def __init__(self) -> None:
        self.terminated = False
        self.killed = False

    def terminate(self) -> None:
        self.terminated = True

    def kill(self) -> None:
        self.killed = True

    def wait(self, timeout: float | None = None) -> int:
        return 0


def _fake_identity(pid: int = _FakeProcess.pid) -> dict[str, object]:
    return {
        "pid": pid,
        "creation_time_100ns": 987654321,
        "executable": r"C:\unit\BridgeWorker.exe",
    }


def _context(root: Path, *, job_id: str = "task_lifecycle") -> JobContext:
    config = root / "config.json"
    config.write_text('{"plot_common":{"gap_mode":"connect"}}', encoding="utf-8")
    data_root = root / "data"
    data_root.mkdir(exist_ok=True)
    return JobContext.create(
        project_root=root,
        bridge_id="unit",
        bridge_name="测试桥梁",
        data_root=data_root,
        start_date="2026-05-01",
        end_date="2026-05-31",
        config_path=config,
        selected_modules=["temperature"],
        options=options_for_modules(["temperature"]),
        job_id=job_id,
    )


def _bind_report_process(context: JobContext, pid: int = 12345) -> None:
    context.report.launch_id = "report-launch-unit"
    context.report.pid = pid
    context.report.process_creation_time_100ns = 123456789
    context.report.process_executable = r"C:\unit\BridgeMonitoringWorkbench.exe"


class TaskLauncherLifecycleTests(unittest.TestCase):
    def test_atomic_json_publish_retries_permission_error_without_residue(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            target = Path(folder) / "status.json"
            original_replace = Path.replace
            attempts: list[Path] = []

            def flaky_replace(source: Path, destination: Path) -> Path:
                attempts.append(source)
                if len(attempts) < 3:
                    raise PermissionError("synthetic file sharing race")
                return original_replace(source, destination)

            with patch.object(Path, "replace", new=flaky_replace), patch(
                "workbench.process_utils.time.sleep"
            ) as sleep:
                atomic_write_json(target, {"state": "running"})

            self.assertEqual(len(attempts), 3)
            self.assertEqual(sleep.call_count, 2)
            self.assertEqual(
                json.loads(target.read_text(encoding="utf-8"))["state"],
                "running",
            )
            self.assertEqual(list(target.parent.glob(".*.tmp")), [])

    def test_bounded_process_exit_wait_is_deterministic(self) -> None:
        with patch(
            "workbench.report_task.pid_running", side_effect=[True, False]
        ), patch("workbench.report_task.time.sleep") as sleep:
            self.assertTrue(_wait_for_process_exit(12345))
        sleep.assert_called_once()

        with patch(
            "workbench.report_task.pid_running", return_value=True
        ), patch(
            "workbench.report_task.time.monotonic", side_effect=[0.0, 2.1]
        ), patch("workbench.report_task.time.sleep") as sleep:
            self.assertFalse(_wait_for_process_exit(12345, timeout_seconds=2.0))
        sleep.assert_not_called()

    def test_job_context_write_is_atomic_and_leaves_no_temporary_file(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            context = _context(Path(folder))

            target = context.write()
            loaded = JobContext.read(target)

            self.assertEqual(loaded.job_id, context.job_id)
            self.assertEqual(loaded.config_sha256, context.config_sha256)
            self.assertEqual(
                list(target.parent.glob(f".{target.name}.*.tmp")),
                [],
            )

    def test_shared_process_probe_handles_invalid_and_current_pid(self) -> None:
        self.assertFalse(pid_running(None))
        self.assertFalse(pid_running(0))
        self.assertFalse(pid_running(-1))
        self.assertTrue(pid_running(os.getpid()))

    def test_exact_process_termination_uses_captured_child_identity(self) -> None:
        current = process_identity(os.getpid())
        assert current is not None
        child = subprocess.Popen(
            [
                str(current["executable"]),
                "-c",
                "import time; time.sleep(30)",
            ],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            creationflags=(subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0),
        )
        try:
            identity = capture_process_identity(child.pid)
            self.assertIsNotNone(identity)
            assert identity is not None
            self.assertTrue(
                terminate_exact_process(
                    child.pid,
                    int(identity["creation_time_100ns"]),
                    str(identity["executable"]),
                )
            )
            child.wait(timeout=5)
            self.assertFalse(pid_running(child.pid))
        finally:
            if child.poll() is None:
                child.kill()
                child.wait(timeout=5)
        identity = process_identity(os.getpid())
        self.assertIsNotNone(identity)
        assert identity is not None
        self.assertTrue(process_matches(
            os.getpid(),
            identity["creation_time_100ns"],
            identity["executable"],
        ))
        self.assertFalse(process_matches(
            os.getpid(),
            int(identity["creation_time_100ns"]) + 1,
            identity["executable"],
        ))
        # The destructive helper must fail closed on an identity mismatch and
        # leave the current test process alive.
        self.assertFalse(terminate_exact_process(
            os.getpid(),
            int(identity["creation_time_100ns"]) + 1,
            identity["executable"],
        ))
        self.assertTrue(pid_running(os.getpid()))

    def test_spawned_identity_uses_original_process_handle(self) -> None:
        child = subprocess.Popen(
            [sys.executable, "-c", "import time; time.sleep(30)"],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            creationflags=(subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0),
        )
        try:
            identity = capture_spawned_process_identity(child)
            self.assertIsNotNone(identity)
            assert identity is not None
            self.assertEqual(identity["pid"], child.pid)
        finally:
            if child.poll() is None:
                child.kill()
            child.wait(timeout=5)
        # A finished Popen handle must never fall back to reopening a possibly
        # reused PID.
        self.assertIsNone(capture_spawned_process_identity(child))

    def test_process_lease_is_fail_closed_and_reclaims_reused_pid(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            lease = Path(folder) / "active.json"
            identity = process_identity(os.getpid())
            assert identity is not None
            publish_process_lease(
                lease,
                task_type="analysis",
                launch_id="live",
                pid=os.getpid(),
                process_creation_time_100ns=int(identity["creation_time_100ns"]),
                process_executable=str(identity["executable"]),
                context_path=Path(folder) / "job.json",
            )
            with self.assertRaisesRegex(RuntimeError, "已有后台进程"):
                assert_no_live_process_lease(lease, "分析任务")
            self.assertTrue(lease.is_file())

            payload = json.loads(lease.read_text(encoding="utf-8"))
            payload["process_creation_time_100ns"] += 1
            atomic_write_json(lease, payload)
            assert_no_live_process_lease(lease, "分析任务")
            self.assertFalse(lease.exists())

            self.assertEqual(
                process_identity_state(
                    os.getpid(),
                    int(identity["creation_time_100ns"]),
                    str(identity["executable"]),
                ),
                "matching",
            )
            with patch(
                "workbench.process_utils.process_identity", return_value=None
            ), patch("workbench.process_utils.pid_running", return_value=True):
                self.assertEqual(
                    process_identity_state(
                        os.getpid(),
                        int(identity["creation_time_100ns"]),
                        str(identity["executable"]),
                    ),
                    "unverifiable",
                )

    def test_file_lock_rejects_a_second_process(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            lock = Path(folder) / "shared.lock"
            release = Path(folder) / "release.flag"
            code = """
import sys, time
from pathlib import Path
from workbench.process_utils import exclusive_file_lock
with exclusive_file_lock(Path(sys.argv[1])):
    print('ready', flush=True)
    while not Path(sys.argv[2]).exists():
        time.sleep(0.02)
print('released', flush=True)
"""
            child = subprocess.Popen(
                [sys.executable, "-c", code, str(lock), str(release)],
                cwd=Path(__file__).resolve().parents[1],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                creationflags=(subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0),
            )
            try:
                assert child.stdout is not None
                self.assertEqual(child.stdout.readline().strip(), "ready")
                with self.assertRaisesRegex(RuntimeError, "另一个工作台"):
                    with exclusive_file_lock(lock):
                        self.fail("second process unexpectedly acquired the lock")
            finally:
                release.write_text("release", encoding="utf-8")
                if child.stdout is not None:
                    self.assertEqual(child.stdout.readline().strip(), "released")
                child.wait(timeout=5)
                if child.stdout is not None:
                    child.stdout.close()
                if child.stderr is not None:
                    child.stderr.close()

    def test_resolver_discovers_packaged_runner_before_matlab(self) -> None:
        with tempfile.TemporaryDirectory() as folder, patch(
            "workbench.analysis.shutil.which", return_value=r"C:\\MATLAB\\matlab.exe"
        ):
            root = Path(folder)
            exe_name = "BridgeAnalysisRunner.exe" if os.name == "nt" else "BridgeAnalysisRunner"
            runner = root / "dist" / "BridgeAnalysisRunner" / exe_name
            runner.parent.mkdir(parents=True)
            runner.write_bytes(b"runner")

            executor = ExecutorResolver(root).resolve()

            self.assertEqual(executor.kind, "compiled_runner")
            self.assertEqual(executor.executable, runner.resolve())

    def test_resolver_uses_explicit_matlab_and_rejects_missing_executor(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            matlab = root / "matlab.exe"
            matlab.write_bytes(b"matlab")
            executor = ExecutorResolver(root).resolve(matlab=matlab)
            self.assertEqual(executor, Executor("matlab_batch", matlab.resolve()))

            with patch("workbench.analysis.shutil.which", return_value=None):
                with self.assertRaisesRegex(FileNotFoundError, "No BridgeAnalysisRunner"):
                    ExecutorResolver(root).resolve()

    def test_analysis_relaunch_removes_stale_stop_flag(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            context = _context(root)
            stop = Path(context.analysis.stop_path)
            stop.parent.mkdir(parents=True)
            stop.write_text("old stop", encoding="utf-8")
            runner = root / "runner.exe"
            runner.write_bytes(b"runner")

            with patch(
                "workbench.analysis.capture_spawned_process_identity",
                return_value=_fake_identity(),
            ):
                result = AnalysisLauncher(
                    root, popen=lambda *_args, **_kwargs: _FakeProcess()
                ).launch(context, Executor("compiled_runner", runner))

            self.assertEqual(result.pid, _FakeProcess.pid)
            self.assertFalse(stop.exists())
            raw_status = json.loads(Path(context.analysis.status_path).read_text(encoding="utf-8"))
            self.assertEqual(raw_status["status"], "prepared")
            self.assertTrue(context.analysis.launch_id)
            self.assertEqual(raw_status["async_run_id"], context.analysis.launch_id)
            self.assertIn(context.analysis.launch_id, Path(context.analysis.request_path).name)
            self.assertIn(context.analysis.launch_id, Path(context.analysis.status_path).name)
            self.assertIn(context.analysis.launch_id, Path(context.analysis.stop_path).name)

    def test_stale_analysis_window_cannot_stop_new_launch(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            context = _context(root)
            runner = root / "runner.exe"
            runner.write_bytes(b"runner")
            with patch(
                "workbench.analysis.capture_spawned_process_identity",
                return_value=_fake_identity(),
            ):
                AnalysisLauncher(
                    root, popen=lambda *_args, **_kwargs: _FakeProcess()
                ).launch(context, Executor("compiled_runner", runner))
                stale = JobContext.read(context.context_path)
                old_launch_id = stale.analysis.launch_id
                old_stop_path = Path(stale.analysis.stop_path)
                AnalysisLauncher(
                    root, popen=lambda *_args, **_kwargs: _FakeProcess()
                ).launch(context, Executor("compiled_runner", runner))

            self.assertNotEqual(old_launch_id, context.analysis.launch_id)
            self.assertFalse(old_stop_path.exists())
            with self.assertRaisesRegex(RuntimeError, "状态已过期"):
                AnalysisLauncher.request_stop(stale)
            current = JobContext.read(context.context_path)
            self.assertEqual(current.analysis.launch_id, context.analysis.launch_id)
            self.assertEqual(current.analysis.state, "launched")
            self.assertFalse(Path(current.analysis.stop_path).exists())

    def test_active_analysis_context_refuses_duplicate_launch(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            context = _context(root)
            runner = root / "runner.exe"
            runner.write_bytes(b"runner")
            identity = process_identity(os.getpid())
            assert identity is not None
            context.analysis.state = "launched"
            context.analysis.launch_id = "already-running"
            context.analysis.pid = os.getpid()
            context.analysis.process_creation_time_100ns = int(
                identity["creation_time_100ns"]
            )
            context.analysis.process_executable = str(identity["executable"])
            context.write()

            popen = Mock()
            with self.assertRaisesRegex(RuntimeError, "已有分析进程"):
                AnalysisLauncher(root, popen=popen).launch(
                    context, Executor("compiled_runner", runner)
                )
            popen.assert_not_called()

    def test_same_data_root_blocks_other_jobs_and_cross_type_launches(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            first = _context(root, job_id="resource-a")
            second = _context(root, job_id="resource-b")
            first.write()
            second.write()
            runner = root / "runner.exe"
            runner.write_bytes(b"runner")
            identity = process_identity(os.getpid())
            assert identity is not None
            process = _FakeProcess()
            process.pid = os.getpid()
            launcher = AnalysisLauncher(
                root, popen=lambda *_args, **_kwargs: process
            )
            with patch(
                "workbench.analysis.capture_spawned_process_identity",
                return_value=identity,
            ):
                launcher.launch(first, Executor("compiled_runner", runner))
                with self.assertRaisesRegex(RuntimeError, "后台进程"):
                    launcher.launch(second, Executor("compiled_runner", runner))
            with patch("workbench.report_task.subprocess.Popen") as report_popen:
                with self.assertRaisesRegex(RuntimeError, "分析任务.*后台进程"):
                    launch_report_job(second, second.context_path)
            report_popen.assert_not_called()

    def test_different_data_roots_can_launch_independently(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            root_a = root / "a"
            root_b = root / "b"
            root_a.mkdir()
            root_b.mkdir()
            first = _context(root_a, job_id="a")
            second = _context(root_b, job_id="b")
            runner_a = root_a / "runner.exe"
            runner_b = root_b / "runner.exe"
            runner_a.write_bytes(b"runner")
            runner_b.write_bytes(b"runner")
            identity = process_identity(os.getpid())
            assert identity is not None
            process_a = _FakeProcess()
            process_b = _FakeProcess()
            process_a.pid = os.getpid()
            process_b.pid = os.getpid()
            with patch(
                "workbench.analysis.capture_spawned_process_identity",
                return_value=identity,
            ):
                AnalysisLauncher(
                    root_a, popen=lambda *_args, **_kwargs: process_a
                ).launch(first, Executor("compiled_runner", runner_a))
                AnalysisLauncher(
                    root_b, popen=lambda *_args, **_kwargs: process_b
                ).launch(second, Executor("compiled_runner", runner_b))

    def test_field_level_persistence_preserves_other_task_state(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            context = _context(root)
            path = context.write()
            analysis_window = JobContext.read(path)
            report_window = JobContext.read(path)

            report_window.report.state = "completed"
            report_window.report.output_docx = str(root / "report.docx")
            self.assertTrue(persist_report_state(report_window))

            analysis_window.analysis.state = "completed"
            analysis_window.analysis.manifest_path = str(root / "manifest.json")
            self.assertTrue(persist_analysis_state(analysis_window))

            saved = JobContext.read(path)
            self.assertEqual(saved.analysis.state, "completed")
            self.assertEqual(saved.report.state, "completed")
            self.assertEqual(saved.report.output_docx, str(root / "report.docx"))

    def test_launch_rejects_context_file_replaced_by_another_job(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            original = _context(root, job_id="original")
            path = original.write()
            stale_window = JobContext.read(path)
            replacement = _context(root, job_id="replacement")
            replacement.write(path)
            runner = root / "runner.exe"
            runner.write_bytes(b"runner")
            popen = Mock()
            with self.assertRaisesRegex(RuntimeError, "另一任务"):
                AnalysisLauncher(root, popen=popen).launch(
                    stale_window, Executor("compiled_runner", runner)
                )
            popen.assert_not_called()

    def test_analysis_spawn_failure_is_durable_terminal_state(self) -> None:
        def fail_spawn(*_args, **_kwargs):
            raise OSError("process creation denied")

        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            context = _context(root)
            runner = root / "runner.exe"
            runner.write_bytes(b"runner")

            with self.assertRaisesRegex(OSError, "creation denied"):
                AnalysisLauncher(root, popen=fail_spawn).launch(
                    context, Executor("compiled_runner", runner)
                )

            status = read_analysis_status(context)
            self.assertEqual(status["status"], "launch_failed")
            self.assertEqual(status["stage"], "process_start")
            saved = JobContext.read(context.context_path)
            self.assertEqual(saved.analysis.state, "launch_failed")
            self.assertIsNone(saved.analysis.pid)

    def test_analysis_prepare_failure_is_durable_terminal_state(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            context = _context(root)
            runner = root / "runner.exe"
            runner.write_bytes(b"runner")
            Path(context.config_path).write_text('{"changed":true}', encoding="utf-8")

            with self.assertRaisesRegex(RuntimeError, "Config changed"):
                AnalysisLauncher(root).launch(
                    context, Executor("compiled_runner", runner)
                )

            saved = JobContext.read(context.context_path)
            self.assertEqual(saved.analysis.state, "launch_failed")
            status = json.loads(
                Path(context.analysis.status_path).read_text(encoding="utf-8")
            )
            self.assertEqual(status["stage"], "prepare")

    def test_analysis_identity_failure_terminates_exact_spawn_and_closes_state(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            context = _context(root)
            runner = root / "runner.exe"
            runner.write_bytes(b"runner")
            process = _FakeProcess()

            with patch(
                "workbench.analysis.capture_spawned_process_identity", return_value=None
            ), self.assertRaisesRegex(RuntimeError, "无法取得"):
                AnalysisLauncher(
                    root, popen=lambda *_args, **_kwargs: process
                ).launch(context, Executor("compiled_runner", runner))

            self.assertTrue(process.terminated)
            saved = JobContext.read(context.context_path)
            self.assertEqual(saved.analysis.state, "launch_failed")
            self.assertIsNone(saved.analysis.pid)

    def test_fast_exit_terminal_publication_is_preserved_without_identity(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            runner = root / "runner.exe"
            runner.write_bytes(b"runner")
            analysis_context = _context(root, job_id="fast-analysis")
            analysis_process = _FakeProcess()

            def publish_analysis_terminal(_process):
                atomic_write_json(
                    analysis_context.analysis.status_path,
                    {
                        "status": "completed",
                        "async_run_id": analysis_context.analysis.launch_id,
                    },
                )
                return None

            with patch(
                "workbench.analysis.capture_spawned_process_identity",
                side_effect=publish_analysis_terminal,
            ):
                AnalysisLauncher(
                    root, popen=lambda *_args, **_kwargs: analysis_process
                ).launch(
                    analysis_context, Executor("compiled_runner", runner)
                )
            self.assertFalse(analysis_process.terminated)
            self.assertEqual(analysis_context.analysis.state, "completed")

        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            report_context = _context(root, job_id="fast-report")
            report_path = report_context.write()
            report_process = _FakeProcess()

            def publish_report_terminal(_process):
                atomic_write_json(
                    report_context.report.result_path,
                    {
                        "state": "completed",
                        "launch_id": report_context.report.launch_id,
                    },
                )
                return None

            with patch(
                "workbench.report_task.subprocess.Popen",
                return_value=report_process,
            ), patch(
                "workbench.report_task.capture_spawned_process_identity",
                side_effect=publish_report_terminal,
            ):
                launch_report_job(report_context, report_path)
            self.assertFalse(report_process.terminated)
            self.assertEqual(report_context.report.state, "completed")

    def test_analysis_rerun_invalidates_old_report_result(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            context = _context(root)
            old_status = Path(context.report.status_path)
            old_result = Path(context.report.result_path)
            old_status.parent.mkdir(parents=True, exist_ok=True)
            context.report.launch_id = "old-report"
            context.report.state = "completed"
            context.report.output_docx = str(root / "old.docx")
            atomic_write_json(
                old_status,
                {"state": "completed", "launch_id": "old-report"},
            )
            atomic_write_json(
                old_result,
                {"state": "completed", "launch_id": "old-report"},
            )
            context.write()
            runner = root / "runner.exe"
            runner.write_bytes(b"runner")
            with patch(
                "workbench.analysis.capture_spawned_process_identity",
                return_value=_fake_identity(),
            ):
                AnalysisLauncher(
                    root, popen=lambda *_args, **_kwargs: _FakeProcess()
                ).launch(context, Executor("compiled_runner", runner))

            self.assertEqual(read_report_status(context)["state"], "blocked")
            self.assertEqual(context.report.launch_id, "")
            self.assertEqual(context.report.output_docx, "")
            self.assertNotEqual(Path(context.report.status_path), old_status)

    def test_analysis_post_spawn_context_failure_terminates_child_and_closes_state(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            context = _context(root)
            runner = root / "runner.exe"
            runner.write_bytes(b"runner")
            process = _FakeProcess()
            real_write = context.write
            calls = 0

            def fail_second_write(path=None):
                nonlocal calls
                calls += 1
                if calls == 2:
                    raise OSError("synthetic final context write failure")
                return real_write(path)

            with patch.object(context, "write", side_effect=fail_second_write), patch(
                "workbench.analysis.capture_spawned_process_identity",
                return_value=_fake_identity(),
            ), self.assertRaisesRegex(OSError, "final context"):
                AnalysisLauncher(
                    root, popen=lambda *_args, **_kwargs: process
                ).launch(context, Executor("compiled_runner", runner))

            self.assertTrue(process.terminated)
            saved = JobContext.read(context.context_path)
            self.assertEqual(saved.analysis.state, "launch_failed")
            self.assertIsNone(saved.analysis.pid)
            self.assertEqual(saved.analysis.executor_type, "compiled_runner")

    def test_analysis_process_exit_without_terminal_status_is_not_left_prepared(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            context = _context(root)
            context.analysis.state = "launched"
            context.analysis.pid = 424242
            status_path = Path(context.analysis.status_path)
            status_path.parent.mkdir(parents=True)
            status_path.write_text(
                '{"status":"prepared","progress_fraction":0.0}', encoding="utf-8"
            )

            with patch("workbench.analysis.pid_running", return_value=False):
                status = read_analysis_status(context)

            self.assertEqual(status["status"], "launch_failed")
            self.assertEqual(status["stage"], "process_exit")
            persisted = json.loads(status_path.read_text(encoding="utf-8"))
            self.assertEqual(persisted["status"], "launch_failed")
            saved = JobContext.read(context.context_path)
            self.assertEqual(saved.analysis.state, "launch_failed")
            self.assertIsNone(saved.analysis.pid)

    def test_analysis_completed_status_is_not_overwritten_when_process_exits(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            context = _context(root)
            context.analysis.state = "launched"
            context.analysis.pid = 424242
            status_path = Path(context.analysis.status_path)
            status_path.parent.mkdir(parents=True)
            completed = {
                "status": "completed",
                "progress_fraction": 1.0,
                "manifest_path": str(root / "analysis_manifest.json"),
            }
            status_path.write_text(json.dumps(completed), encoding="utf-8")

            with patch("workbench.analysis.pid_running", return_value=False):
                status = read_analysis_status(context)

            self.assertEqual(status, completed)
            self.assertEqual(json.loads(status_path.read_text(encoding="utf-8")), completed)

    def test_analysis_completion_published_during_pid_probe_wins_race(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            context = _context(root)
            context.analysis.state = "running"
            context.analysis.pid = 424242
            status_path = Path(context.analysis.status_path)
            status_path.parent.mkdir(parents=True)
            status_path.write_text('{"status":"running"}', encoding="utf-8")
            completed = {
                "status": "completed",
                "manifest_path": str(root / "analysis_manifest.json"),
            }

            def finish_then_exit(_pid):
                status_path.write_text(json.dumps(completed), encoding="utf-8")
                return False

            with patch("workbench.analysis.pid_running", side_effect=finish_then_exit):
                status = read_analysis_status(context)

            self.assertEqual(completed, status)
            saved = JobContext.read(context.context_path)
            self.assertEqual("completed", saved.analysis.state)
            self.assertIsNone(saved.analysis.pid)
            self.assertEqual(completed["manifest_path"], saved.analysis.manifest_path)

    def test_analysis_live_process_keeps_nonterminal_status(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            context = _context(root)
            context.analysis.state = "launched"
            context.analysis.pid = 424242

            with patch("workbench.analysis.pid_running", return_value=True):
                without_file = read_analysis_status(context)
                status_path = Path(context.analysis.status_path)
                status_path.parent.mkdir(parents=True)
                status_path.write_text('{"status":"running"}', encoding="utf-8")
                with_file = read_analysis_status(context)

            self.assertEqual(without_file["status"], "launched")
            self.assertEqual(with_file["status"], "running")

    def test_analysis_ignores_terminal_status_from_previous_launch(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            context = _context(root)
            context.analysis.state = "running"
            context.analysis.launch_id = "current-analysis-launch"
            context.analysis.pid = 424242
            status_path = Path(context.analysis.status_path)
            status_path.parent.mkdir(parents=True)
            status_path.write_text(
                json.dumps({"status": "completed", "async_run_id": "old-launch"}),
                encoding="utf-8",
            )

            with patch(
                "workbench.analysis._analysis_process_running", return_value=True
            ):
                status = read_analysis_status(context)

            self.assertEqual(status["status"], "running")
            self.assertEqual(status["stage"], "status_retry")

    def test_analysis_stop_request_is_durable_and_reversible_on_relaunch(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            context = _context(root)
            stop = AnalysisLauncher.request_stop(context)
            self.assertTrue(stop.is_file())
            self.assertEqual(JobContext.read(context.context_path).analysis.state, "stopping")

            runner = root / "runner.exe"
            runner.write_bytes(b"runner")
            with patch(
                "workbench.analysis.capture_spawned_process_identity",
                return_value=_fake_identity(),
            ):
                AnalysisLauncher(
                    root, popen=lambda *_args, **_kwargs: _FakeProcess()
                ).launch(context, Executor("compiled_runner", runner))
            self.assertFalse(stop.exists())

    def test_analysis_stop_then_poll_masks_running_and_persists_stopped(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            context = _context(root)
            context.analysis.state = "running"
            context.analysis.pid = 424242
            status_path = Path(context.analysis.status_path)
            status_path.parent.mkdir(parents=True)
            status_path.write_text(
                '{"status":"running","progress_fraction":0.4}', encoding="utf-8"
            )
            context.write()

            AnalysisLauncher.request_stop(context)
            with patch("workbench.analysis.pid_running", return_value=True):
                stopping = read_analysis_status(context)
            self.assertEqual(stopping["status"], "stopping")
            self.assertEqual(stopping["stage"], "stop_requested")

            with patch("workbench.analysis.pid_running", return_value=False):
                stopped = read_analysis_status(context)
            self.assertEqual(stopped["status"], "stopped")
            self.assertEqual(
                json.loads(status_path.read_text(encoding="utf-8"))["status"],
                "stopped",
            )
            saved = JobContext.read(context.context_path)
            self.assertEqual(saved.analysis.state, "stopped")
            self.assertIsNone(saved.analysis.pid)

    def test_analysis_terminal_status_published_while_stopping_is_preserved(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            context = _context(root)
            context.analysis.state = "stopping"
            context.analysis.pid = 424242
            status_path = Path(context.analysis.status_path)
            status_path.parent.mkdir(parents=True)
            status_path.write_text('{"status":"running"}', encoding="utf-8")
            completed = {"status": "completed", "progress_fraction": 1.0}

            def finish_then_exit(_pid):
                status_path.write_text(json.dumps(completed), encoding="utf-8")
                return False

            with patch("workbench.analysis.pid_running", side_effect=finish_then_exit):
                status = read_analysis_status(context)

            self.assertEqual(completed, status)
            self.assertEqual("completed", JobContext.read(context.context_path).analysis.state)

    def test_analysis_non_object_status_retries_while_process_is_live(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            context = _context(root)
            context.analysis.state = "running"
            context.analysis.pid = 424242
            status_path = Path(context.analysis.status_path)
            status_path.parent.mkdir(parents=True)
            status_path.write_text("[]", encoding="utf-8")

            with patch("workbench.analysis.pid_running", return_value=True):
                status = read_analysis_status(context)

            self.assertEqual("running", status["status"])
            self.assertEqual("status_retry", status["stage"])

    def test_analysis_partial_status_keeps_live_task_nonrestartable(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            context = _context(root)
            context.analysis.state = "running"
            context.analysis.pid = 424242
            status_path = Path(context.analysis.status_path)
            status_path.parent.mkdir(parents=True)
            status_path.write_text('{"status":', encoding="utf-8")

            with patch("workbench.analysis.pid_running", return_value=True):
                status = read_analysis_status(context)

            self.assertEqual(status["status"], "running")
            self.assertEqual(status["stage"], "status_retry")
            self.assertIn("自动重试", status["message"])

    def test_report_spawn_failure_replaces_stale_result_with_terminal_failure(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            context = _context(root)
            context_path = context.write()
            legacy_status = context_path.parent / "report_status.json"
            legacy_result = context_path.parent / "report_result.json"
            legacy_status.write_text(
                '{"state":"completed","message":"old"}', encoding="utf-8"
            )
            legacy_result.write_text(
                '{"state":"completed","message":"old"}', encoding="utf-8"
            )

            with patch("workbench.report_task.subprocess.Popen", side_effect=OSError("spawn denied")):
                with self.assertRaisesRegex(OSError, "spawn denied"):
                    launch_report_job(context, context_path)

            result_path = Path(context.report.result_path)
            result = json.loads(result_path.read_text(encoding="utf-8"))
            self.assertEqual(result["state"], "launch_failed")
            self.assertNotEqual(result["message"], "old")
            self.assertEqual(
                json.loads(legacy_result.read_text(encoding="utf-8"))["message"],
                "old",
            )
            self.assertEqual(read_report_status(context)["state"], "launch_failed")
            saved = JobContext.read(context_path)
            self.assertEqual(saved.report.state, "launch_failed")
            self.assertIsNone(saved.report.pid)

    def test_report_prepare_failure_is_durable_terminal_state(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            context = _context(root)
            context_path = context.write()

            with patch.object(Path, "unlink", side_effect=PermissionError("locked")):
                with self.assertRaisesRegex(PermissionError, "locked"):
                    launch_report_job(context, context_path)

            saved = JobContext.read(context_path)
            self.assertEqual(saved.report.state, "launch_failed")
            self.assertEqual(read_report_status(saved)["stage"], "prepare")

    def test_report_identity_failure_terminates_exact_spawn_and_closes_state(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            context = _context(root)
            context_path = context.write()
            process = _FakeProcess()

            with patch(
                "workbench.report_task.subprocess.Popen", return_value=process
            ), patch(
                "workbench.report_task.capture_spawned_process_identity", return_value=None
            ), self.assertRaisesRegex(RuntimeError, "无法取得"):
                launch_report_job(context, context_path)

            self.assertTrue(process.terminated)
            saved = JobContext.read(context_path)
            self.assertEqual(saved.report.state, "launch_failed")
            self.assertIsNone(saved.report.pid)

    def test_report_post_spawn_context_failure_terminates_child_and_closes_state(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            context = _context(root)
            context_path = context.write()
            process = _FakeProcess()
            real_write = context.write
            calls = 0

            def fail_second_write(path=None):
                nonlocal calls
                calls += 1
                if calls == 2:
                    raise OSError("synthetic final context write failure")
                return real_write(path)

            with patch.object(context, "write", side_effect=fail_second_write), patch(
                "workbench.report_task.subprocess.Popen", return_value=process
            ), patch(
                "workbench.report_task.capture_spawned_process_identity",
                return_value=_fake_identity(),
            ), self.assertRaisesRegex(OSError, "final context"):
                launch_report_job(context, context_path)

            self.assertTrue(process.terminated)
            saved = JobContext.read(context_path)
            self.assertEqual(saved.report.state, "launch_failed")
            self.assertIsNone(saved.report.pid)

    def test_report_success_records_process_and_runtime_paths(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            context = _context(root)
            context_path = context.write()

            with patch(
                "workbench.report_task.subprocess.Popen", return_value=_FakeProcess()
            ), patch(
                "workbench.report_task.capture_spawned_process_identity",
                return_value=_fake_identity(),
            ):
                result = launch_report_job(context, context_path)

            self.assertEqual(result.pid, _FakeProcess.pid)
            saved = JobContext.read(context_path)
            self.assertEqual(saved.report.state, "launched")
            self.assertEqual(saved.report.pid, _FakeProcess.pid)
            self.assertTrue(saved.report.launch_id)
            self.assertEqual(Path(saved.report.status_path), result.status_path)
            self.assertEqual(Path(saved.report.result_path), result.result_path)
            self.assertIn(saved.report.launch_id, result.status_path.name)
            self.assertIn(saved.report.launch_id, result.result_path.name)
            launch_flag = result.command.index("--report-launch-id")
            self.assertEqual(result.command[launch_flag + 1], saved.report.launch_id)

    def test_report_launch_uses_immutable_snapshot_with_current_ui_inputs(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            context = _context(root)
            template = root / "template.docx"
            template.write_bytes(b"current template")
            requested_output = root / "requested-output"
            context.report.template_path = str(template)
            context.report.template_sha256 = file_sha256(template)
            context.report.output_dir = str(requested_output)
            context.report.report_type = "unit-monthly"
            context.report.plots_approved = True
            context.report.state = "ready"
            context_path = context.write()
            identity = process_identity(os.getpid())
            assert identity is not None
            process = _FakeProcess()
            process.pid = os.getpid()

            with patch(
                "workbench.report_task.subprocess.Popen", return_value=process
            ), patch(
                "workbench.report_task.capture_spawned_process_identity",
                return_value=identity,
            ):
                result = launch_report_job(context, context_path)

            context_arg = result.command.index("--job-context")
            snapshot_path = Path(result.command[context_arg + 1])
            self.assertNotEqual(snapshot_path, context_path)
            self.assertEqual(
                snapshot_path.parent,
                Path(context.analysis.request_path).parent.resolve(),
            )
            snapshot = JobContext.read(snapshot_path)
            self.assertEqual(snapshot.report.output_dir, str(requested_output))
            self.assertEqual(snapshot.report.template_path, str(template))
            self.assertTrue(snapshot.report.plots_approved)

            context.report.output_dir = str(root / "changed-after-launch")
            context.write(context_path)
            unchanged = JobContext.read(snapshot_path)
            self.assertEqual(unchanged.report.output_dir, str(requested_output))

    def test_terminal_persistence_retries_after_transient_write_failure(self) -> None:
        for task_kind in ("analysis", "report"):
            with self.subTest(task_kind=task_kind), tempfile.TemporaryDirectory() as folder:
                root = Path(folder)
                context = _context(root)
                if task_kind == "analysis":
                    context.analysis.state = "launched"
                    context.analysis.launch_id = "analysis-retry"
                    status_path = Path(context.analysis.status_path)
                else:
                    context.report.state = "launched"
                    context.report.launch_id = "report-retry"
                    status_path = Path(context.report.status_path)
                context_path = context.write()
                status_path.parent.mkdir(parents=True, exist_ok=True)
                if task_kind == "analysis":
                    atomic_write_json(
                        status_path,
                        {"status": "completed", "async_run_id": "analysis-retry"},
                    )
                else:
                    atomic_write_json(
                        status_path,
                        {"state": "running", "launch_id": "report-retry"},
                    )
                    atomic_write_json(
                        context.report.result_path,
                        {"state": "completed", "launch_id": "report-retry"},
                    )

                original_write = JobContext.write
                calls = 0

                def fail_once(instance, path=None):
                    nonlocal calls
                    calls += 1
                    if calls == 1:
                        raise OSError("synthetic transient context write")
                    return original_write(instance, path)

                with patch.object(JobContext, "write", new=fail_once):
                    if task_kind == "analysis":
                        self.assertEqual(
                            read_analysis_status(context)["status"], "completed"
                        )
                        self.assertEqual(context.analysis.state, "launched")
                        self.assertEqual(
                            read_analysis_status(context)["status"], "completed"
                        )
                        self.assertEqual(context.analysis.state, "completed")
                    else:
                        self.assertEqual(
                            read_report_status(context)["state"], "completed"
                        )
                        self.assertEqual(context.report.state, "launched")
                        self.assertEqual(
                            read_report_status(context)["state"], "completed"
                        )
                        self.assertEqual(context.report.state, "completed")
                saved = JobContext.read(context_path)
                if task_kind == "analysis":
                    self.assertEqual(saved.analysis.state, "completed")
                else:
                    self.assertEqual(saved.report.state, "completed")

    def test_report_status_only_completed_remains_finalizing_until_result(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            context = _context(root)
            identity = process_identity(os.getpid())
            assert identity is not None
            context.report.state = "running"
            context.report.launch_id = "report-finalizing"
            context.report.pid = os.getpid()
            context.report.process_creation_time_100ns = int(
                identity["creation_time_100ns"]
            )
            context.report.process_executable = str(identity["executable"])
            context.write()
            atomic_write_json(
                context.report.status_path,
                {
                    "state": "completed",
                    "launch_id": "report-finalizing",
                    "stage": "completed",
                },
            )

            status = read_report_status(context)

            self.assertEqual(status["state"], "running")
            self.assertEqual(status["stage"], "finalizing")
            self.assertEqual(context.report.pid, os.getpid())

    def test_moved_context_keeps_launch_protocol_files_beside_opened_task(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            context = _context(root)
            original = context.write()
            moved_dir = root / "moved-task"
            moved_dir.mkdir()
            moved_path = moved_dir / "job_context.json"
            moved_path.write_bytes(original.read_bytes())
            moved = JobContext.read(moved_path)
            runner = root / "runner.exe"
            runner.write_bytes(b"runner")
            executor = Executor("compiled_runner", runner)

            with patch(
                "workbench.analysis.capture_spawned_process_identity",
                return_value=_fake_identity(),
            ):
                AnalysisLauncher(root, popen=lambda *_args, **_kwargs: _FakeProcess()).launch(
                    moved, executor
                )

            self.assertEqual(Path(moved.analysis.request_path).parent, moved_dir.resolve())
            self.assertEqual(Path(moved.analysis.status_path).parent, moved_dir.resolve())
            self.assertEqual(Path(moved.analysis.stdout_log).parent, moved_dir.resolve())

    def test_report_uses_explicit_runtime_root_after_context_is_moved(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            alternate_root = root / "installed"
            alternate_root.mkdir()
            context = _context(root)
            context.report.output_dir = str(root / "output")
            context.report.plots_approved = True
            context.report.state = "ready"
            original = context.write()
            moved_dir = root / "moved-report-task"
            moved_dir.mkdir()
            moved_path = moved_dir / "job_context.json"
            moved_path.write_bytes(original.read_bytes())
            moved = JobContext.read(moved_path)

            with patch(
                "workbench.report_task.subprocess.Popen", return_value=_FakeProcess()
            ) as popen, patch(
                "workbench.report_task.capture_spawned_process_identity",
                return_value=_fake_identity(),
            ):
                launch = launch_report_job(
                    moved,
                    moved_path,
                    runtime_root=alternate_root,
                )

            self.assertEqual(launch.status_path.parent, moved_dir.resolve())
            project_arg = launch.command.index("--project-root")
            self.assertEqual(Path(launch.command[project_arg + 1]), alternate_root.resolve())
            self.assertEqual(Path(popen.call_args.kwargs["cwd"]), alternate_root.resolve())

    def test_report_output_directory_blocks_different_data_roots(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            first_root = root / "first"
            second_root = root / "second"
            first_root.mkdir()
            second_root.mkdir()
            first = _context(first_root, job_id="report-first")
            second = _context(second_root, job_id="report-second")
            shared_output = root / "shared-output"
            for context in (first, second):
                context.report.output_dir = str(shared_output)
                context.report.plots_approved = True
                context.report.state = "ready"
                context.write()

            identity = process_identity(os.getpid())
            assert identity is not None
            process = _FakeProcess()
            process.pid = os.getpid()
            with patch(
                "workbench.report_task.subprocess.Popen", return_value=process
            ), patch(
                "workbench.report_task.capture_spawned_process_identity",
                return_value=identity,
            ):
                launch_report_job(first)
            with patch("workbench.report_task.subprocess.Popen") as popen:
                with self.assertRaisesRegex(RuntimeError, "报告任务"):
                    launch_report_job(second)
            popen.assert_not_called()

    def test_terminal_result_waits_for_owner_process_cleanup(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            identity = process_identity(os.getpid())
            assert identity is not None

            analysis_context = _context(root, job_id="cleanup-analysis")
            analysis_context.analysis.state = "running"
            analysis_context.analysis.launch_id = "cleanup-analysis-launch"
            analysis_context.analysis.pid = os.getpid()
            analysis_context.analysis.process_creation_time_100ns = int(
                identity["creation_time_100ns"]
            )
            analysis_context.analysis.process_executable = str(identity["executable"])
            analysis_context.write()
            atomic_write_json(
                analysis_context.analysis.status_path,
                {
                    "status": "completed",
                    "async_run_id": "cleanup-analysis-launch",
                },
            )
            analysis_status = read_analysis_status(analysis_context)
            self.assertTrue(analysis_status["process_cleanup_pending"])
            self.assertEqual(analysis_context.analysis.state, "running")
            self.assertEqual(analysis_context.analysis.pid, os.getpid())

        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            report_context = _context(root, job_id="cleanup-report")
            report_context.report.state = "running"
            report_context.report.launch_id = "cleanup-report-launch"
            report_context.report.pid = os.getpid()
            report_context.report.process_creation_time_100ns = int(
                identity["creation_time_100ns"]
            )
            report_context.report.process_executable = str(identity["executable"])
            report_context.write()
            atomic_write_json(
                report_context.report.result_path,
                {"state": "completed", "launch_id": "cleanup-report-launch"},
            )
            report_status = read_report_status(report_context)
            self.assertTrue(report_status["process_cleanup_pending"])
            self.assertEqual(report_context.report.state, "running")
            self.assertEqual(report_context.report.pid, os.getpid())

    def test_active_report_context_refuses_duplicate_launch(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            context = _context(root)
            identity = process_identity(os.getpid())
            assert identity is not None
            context.report.state = "running"
            context.report.launch_id = "already-running"
            context.report.pid = os.getpid()
            context.report.process_creation_time_100ns = int(
                identity["creation_time_100ns"]
            )
            context.report.process_executable = str(identity["executable"])
            context_path = context.write()

            with patch("workbench.report_task.subprocess.Popen") as popen:
                with self.assertRaisesRegex(RuntimeError, "已有报告进程"):
                    launch_report_job(context, context_path)
            popen.assert_not_called()

    def test_report_stop_terminates_exact_process_and_persists_state(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            context = _context(root)
            context.report.state = "running"
            _bind_report_process(context)
            context.write()
            status_path = Path(context.report.status_path)
            status_path.write_text(
                '{"state":"running","progress_fraction":0.4}', encoding="utf-8"
            )
            with patch(
                "workbench.report_task.terminate_exact_process", return_value=True
            ) as terminate, patch(
                "workbench.report_task._wait_for_process_exit", return_value=True
            ):
                terminate_report_job(context)

            terminate.assert_called_once()
            saved = JobContext.read(context.context_path)
            self.assertEqual(saved.report.state, "stopped")
            self.assertIsNone(saved.report.pid)
            self.assertEqual(read_report_status(saved)["state"], "stopped")
            self.assertEqual(
                json.loads(status_path.read_text(encoding="utf-8"))["state"],
                "stopped",
            )
            self.assertEqual(
                json.loads(Path(context.report.result_path).read_text(encoding="utf-8"))["state"],
                "stopped",
            )

    def test_report_stop_failure_keeps_running_pid_and_raises(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            context = _context(root)
            context.report.state = "running"
            _bind_report_process(context)
            context.write()
            status_path = Path(context.report.status_path)
            status_path.write_text('{"state":"running"}', encoding="utf-8")
            with patch(
                "workbench.report_task.terminate_exact_process", return_value=False
            ) as terminate:
                with self.assertRaisesRegex(RuntimeError, "安全终止"):
                    terminate_report_job(context)

            saved = JobContext.read(context.context_path)
            self.assertEqual(saved.report.state, "running")
            self.assertEqual(saved.report.pid, 12345)
            self.assertEqual(
                json.loads(status_path.read_text(encoding="utf-8"))["state"],
                "running",
            )
            self.assertFalse(Path(context.report.result_path).exists())

    def test_report_stop_timeout_keeps_identity_for_retry(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            context = _context(root)
            context.report.state = "running"
            _bind_report_process(context)
            context.write()
            with patch(
                "workbench.report_task.terminate_exact_process",
                side_effect=TimeoutError("synthetic wait timeout"),
            ):
                with self.assertRaisesRegex(RuntimeError, "尚未确认退出"):
                    terminate_report_job(context)
            saved = JobContext.read(context.context_path)
            self.assertEqual(saved.report.state, "running")
            self.assertEqual(saved.report.pid, 12345)
            self.assertTrue(saved.report.process_executable)

    def test_report_stop_refuses_reused_pid_without_unsafe_pid_kill(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            context = _context(root)
            context.report.state = "running"
            _bind_report_process(context)
            context.write()
            with patch(
                "workbench.report_task.terminate_exact_process", return_value=False
            ) as terminate:
                with self.assertRaisesRegex(RuntimeError, "安全终止"):
                    terminate_report_job(context)
            terminate.assert_called_once()
            saved = JobContext.read(context.context_path)
            self.assertEqual(saved.report.state, "running")
            self.assertEqual(saved.report.pid, 12345)

    def test_report_stop_preserves_completion_published_during_termination(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            context = _context(root)
            context.report.state = "running"
            _bind_report_process(context)
            context.write()
            status_path = Path(context.report.status_path)
            result_path = Path(context.report.result_path)
            status_path.write_text(
                '{"state":"running","progress_fraction":0.9}', encoding="utf-8"
            )

            def finish_while_stopping(*_args, **_kwargs):
                result_path.write_text(
                    json.dumps(
                        {
                            "state": "completed",
                            "launch_id": context.report.launch_id,
                            "progress_fraction": 1.0,
                            "report_path": str(root / "report.docx"),
                        }
                    ),
                    encoding="utf-8",
                )
                return True

            with patch(
                "workbench.report_task.terminate_exact_process",
                side_effect=finish_while_stopping,
            ), patch(
                "workbench.report_task._wait_for_process_exit", return_value=True
            ):
                terminate_report_job(context)

            self.assertEqual(
                json.loads(result_path.read_text(encoding="utf-8"))["state"],
                "completed",
            )
            self.assertEqual(
                json.loads(status_path.read_text(encoding="utf-8"))["state"],
                "running",
            )
            saved = JobContext.read(context.context_path)
            self.assertEqual(saved.report.state, "completed")
            self.assertIsNone(saved.report.pid)

    def test_report_stop_preserves_live_owner_after_terminal_result_wins(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            context = _context(root)
            identity = process_identity(os.getpid())
            assert identity is not None
            context.report.state = "running"
            context.report.launch_id = "report-stop-race"
            context.report.pid = os.getpid()
            context.report.process_creation_time_100ns = int(
                identity["creation_time_100ns"]
            )
            context.report.process_executable = str(identity["executable"])
            context.write()
            atomic_write_json(
                context.report.result_path,
                {"state": "completed", "launch_id": "report-stop-race"},
            )

            outcome = terminate_report_job(context)

            self.assertEqual(outcome, "completed_cleanup_pending")
            saved = JobContext.read(context.context_path)
            self.assertEqual(saved.report.state, "completed")
            self.assertEqual(saved.report.pid, os.getpid())

    def test_launch_rejects_in_memory_data_root_that_differs_from_task_file(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            context = _context(root)
            context.write()
            context.data_root = str(root / "wrong-data-root")
            runner = root / "runner.exe"
            runner.write_bytes(b"runner")
            executor = Executor("compiled_runner", runner)

            with patch("workbench.analysis.subprocess.Popen") as popen:
                with self.assertRaisesRegex(RuntimeError, "数据目录"):
                    AnalysisLauncher(root).launch(context, executor)
            popen.assert_not_called()

    def test_report_unexpected_exit_persists_launch_failed(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            context = _context(root)
            context.report.state = "running"
            context.report.pid = 12345
            context.write()
            status_path = Path(context.report.status_path)
            status_path.write_text('{"state":"running"}', encoding="utf-8")

            with patch("workbench.report_task.pid_running", return_value=False):
                status = read_report_status(context)

            self.assertEqual(status["state"], "launch_failed")
            self.assertEqual(status["stage"], "process_exit")
            self.assertEqual(
                json.loads(status_path.read_text(encoding="utf-8"))["state"],
                "launch_failed",
            )
            self.assertEqual(
                json.loads(Path(context.report.result_path).read_text(encoding="utf-8"))["state"],
                "launch_failed",
            )
            saved = JobContext.read(context.context_path)
            self.assertEqual(saved.report.state, "launch_failed")
            self.assertIsNone(saved.report.pid)

    def test_report_partial_status_keeps_live_task_nonrestartable(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            context = _context(root)
            context.report.state = "running"
            context.report.pid = 12345
            status_path = Path(context.report.status_path)
            status_path.parent.mkdir(parents=True, exist_ok=True)
            status_path.write_text('{"state":', encoding="utf-8")

            with patch("workbench.report_task.pid_running", return_value=True):
                status = read_report_status(context)

            self.assertEqual("running", status["state"])
            self.assertEqual("status_retry", status["stage"])

    def test_report_invalid_utf8_status_retries_while_process_is_live(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            context = _context(root)
            context.report.state = "running"
            context.report.pid = 12345
            status_path = Path(context.report.status_path)
            status_path.parent.mkdir(parents=True, exist_ok=True)
            status_path.write_bytes(b"\xff\xfe\xfa")

            with patch("workbench.report_task.pid_running", return_value=True):
                status = read_report_status(context)

            self.assertEqual("running", status["state"])
            self.assertEqual("status_retry", status["stage"])

    def test_report_ignores_result_from_previous_launch(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            context = _context(root)
            context.report.state = "running"
            context.report.launch_id = "current-report-launch"
            context.report.pid = 12345
            result_path = Path(context.report.result_path)
            result_path.parent.mkdir(parents=True, exist_ok=True)
            result_path.write_text(
                json.dumps({
                    "state": "completed",
                    "launch_id": "old-report-launch",
                    "report_path": "old.docx",
                }),
                encoding="utf-8",
            )

            with patch(
                "workbench.report_task._report_process_running", return_value=True
            ):
                status = read_report_status(context)

            self.assertEqual(status["state"], "running")
            self.assertNotEqual(status.get("report_path"), "old.docx")

    def test_report_completion_published_during_pid_probe_wins_race(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            context = _context(root)
            context.report.state = "running"
            context.report.pid = 12345
            context.write()
            status_path = Path(context.report.status_path)
            result_path = Path(context.report.result_path)
            status_path.write_text('{"state":"running"}', encoding="utf-8")
            completed = {"state": "completed", "report_path": "done.docx"}

            def finish_then_exit(_pid):
                result_path.write_text(json.dumps(completed), encoding="utf-8")
                return False

            with patch("workbench.report_task.pid_running", side_effect=finish_then_exit):
                status = read_report_status(context)

            self.assertEqual("completed", status["state"])
            saved = JobContext.read(context.context_path)
            self.assertEqual("completed", saved.report.state)
            self.assertIsNone(saved.report.pid)


@unittest.skipIf(QApplication is None, "PySide6 is not installed")
class WorkbenchTaskLifecycleGuiTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.app = QApplication.instance() or QApplication([])

    def _window_and_context(self, root: Path) -> tuple[WorkbenchWindow, JobContext]:
        context = _context(root, job_id="gui_lifecycle")
        window = WorkbenchWindow(Path(__file__).resolve().parents[1])
        window.current_context = context
        return window, context

    def test_gui_analysis_start_success_updates_controls(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            window, context = self._window_and_context(root)
            runner = root / "runner.exe"
            runner.write_bytes(b"runner")
            executor = Executor("compiled_runner", runner)

            def build_context() -> JobContext:
                window.current_context = context
                return context

            try:
                with patch.object(window, "_validate_inputs", return_value=[]), patch.object(
                    window, "_build_context", side_effect=build_context
                ), patch("workbench.main_window.ExecutorResolver.resolve", return_value=executor), patch(
                    "workbench.main_window.AnalysisLauncher.launch",
                    return_value=LaunchResult(_FakeProcess.pid, executor, (str(runner),)),
                ):
                    window._start_analysis()

                self.assertFalse(window.start_btn.isEnabled())
                self.assertTrue(window.stop_btn.isEnabled())
                self.assertIn(str(_FakeProcess.pid), window.analysis_status_label.text())
                self.assertIn(context.context_path, window.known_context_paths)
            finally:
                window.poll_timer.stop()
                window.close()

    def test_gui_analysis_start_failure_keeps_retry_available(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            window, context = self._window_and_context(root)
            try:
                with patch.object(window, "_validate_inputs", return_value=[]), patch.object(
                    window, "_build_context", return_value=context
                ), patch("workbench.main_window.ExecutorResolver.resolve", side_effect=FileNotFoundError("none")), patch.object(
                    window, "_show_exception"
                ) as show:
                    window._start_analysis()

                show.assert_called_once()
                self.assertTrue(window.start_btn.isEnabled())
                self.assertFalse(window.stop_btn.isEnabled())
            finally:
                window.poll_timer.stop()
                window.close()

    def test_gui_stop_button_writes_stop_request(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            window, context = self._window_and_context(root)
            window.stop_btn.setEnabled(True)
            try:
                window._request_stop()
                self.assertFalse(window.stop_btn.isEnabled())
                self.assertTrue(Path(context.analysis.stop_path).is_file())
                self.assertEqual(context.analysis.state, "stopping")
            finally:
                window.poll_timer.stop()
                window.close()

    def test_gui_analysis_stop_then_poll_stays_stopping_with_stop_disabled(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            window, context = self._window_and_context(root)
            context.analysis.state = "running"
            context.analysis.pid = 424242
            status_path = Path(context.analysis.status_path)
            status_path.parent.mkdir(parents=True)
            status_path.write_text('{"status":"running"}', encoding="utf-8")
            context.write()
            window.stop_btn.setEnabled(True)
            try:
                window._request_stop()
                with patch("workbench.analysis.pid_running", return_value=True):
                    window._poll_status()

                self.assertEqual(context.analysis.state, "stopping")
                self.assertFalse(window.stop_btn.isEnabled())
                self.assertIn("stopping", window.analysis_status_label.text())
            finally:
                window.poll_timer.stop()
                window.close()

    def test_gui_partial_analysis_status_does_not_enable_duplicate_start(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            window, context = self._window_and_context(root)
            context.analysis.state = "running"
            context.analysis.pid = 424242
            status_path = Path(context.analysis.status_path)
            status_path.parent.mkdir(parents=True)
            status_path.write_text('{"status":', encoding="utf-8")
            try:
                with patch("workbench.analysis.pid_running", return_value=True):
                    window._poll_status()

                self.assertEqual(context.analysis.state, "running")
                self.assertFalse(window.start_btn.isEnabled())
                self.assertTrue(window.stop_btn.isEnabled())
            finally:
                window.poll_timer.stop()
                window.close()

    def test_gui_report_start_success_updates_embedded_progress(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            window, context = self._window_and_context(root)
            template = root / "template.docx"
            template.write_bytes(b"template")
            manifest = root / "analysis_manifest.json"
            manifest.write_text('{"status":"ok"}', encoding="utf-8")
            context.analysis.manifest_path = str(manifest)
            context.analysis.manifest_sha256 = file_sha256(manifest)
            window.template_edit.setText(str(template))
            window.output_dir_edit.setText(str(root / "output"))
            context_path = context.write()
            launch = ReportLaunchResult(
                ("worker",), _FakeProcess.pid,
                context_path.parent / "report_status.json",
                context_path.parent / "report_result.json",
            )
            try:
                with patch.object(window, "_report_gate_ready", return_value=True), patch(
                    "workbench.main_window.launch_report_job", return_value=launch
                ):
                    window._start_report_job()

                self.assertTrue(window.stop_report_btn.isEnabled())
                self.assertFalse(window.open_report_btn.isEnabled())
                self.assertIn(str(_FakeProcess.pid), window.report_progress_label.text())
                self.assertIn("正在生成", window.report_output_label.text())
            finally:
                window.poll_timer.stop()
                window.close()

    def test_gui_report_start_failure_does_not_enable_stop_controls(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            window, context = self._window_and_context(root)
            template = root / "template.docx"
            template.write_bytes(b"template")
            manifest = root / "analysis_manifest.json"
            manifest.write_text('{"status":"ok"}', encoding="utf-8")
            context.analysis.manifest_path = str(manifest)
            context.analysis.manifest_sha256 = file_sha256(manifest)
            window.template_edit.setText(str(template))
            window.output_dir_edit.setText(str(root / "output"))
            try:
                with patch.object(window, "_report_gate_ready", return_value=True), patch(
                    "workbench.main_window.launch_report_job", side_effect=OSError("spawn denied")
                ), patch.object(window, "_show_exception") as show:
                    window._start_report_job()

                show.assert_called_once()
                self.assertFalse(window.stop_report_btn.isEnabled())
                self.assertNotIn("正在生成", window.report_output_label.text())
            finally:
                window.poll_timer.stop()
                window.close()

    def test_gui_report_stop_then_poll_remains_terminal(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            window, context = self._window_and_context(root)
            context.report.state = "running"
            _bind_report_process(context)
            context.write()
            status_path = Path(context.report.status_path)
            status_path.write_text('{"state":"running"}', encoding="utf-8")
            try:
                with patch(
                    "workbench.report_task.terminate_exact_process",
                    return_value=True,
                ), patch(
                    "workbench.report_task._wait_for_process_exit", return_value=True
                ):
                    window._stop_report_job()
                    window._poll_report_status()

                self.assertEqual(context.report.state, "stopped")
                self.assertFalse(window.stop_report_btn.isEnabled())
                self.assertIn("已停止", window.report_progress_label.text())
            finally:
                window.poll_timer.stop()
                window.close()

    def test_gui_completed_result_keeps_live_report_identity_until_cleanup(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            window, context = self._window_and_context(root)
            identity = process_identity(os.getpid())
            assert identity is not None
            context.report.state = "running"
            context.report.launch_id = "gui-report-cleanup"
            context.report.pid = os.getpid()
            context.report.process_creation_time_100ns = int(
                identity["creation_time_100ns"]
            )
            context.report.process_executable = str(identity["executable"])
            context.write()
            atomic_write_json(
                context.report.result_path,
                {
                    "state": "completed",
                    "launch_id": "gui-report-cleanup",
                    "report_path": str(root / "report.docx"),
                    "qc": {"status": "ok"},
                },
            )
            try:
                window._poll_report_status()

                self.assertEqual(context.report.pid, os.getpid())
                self.assertEqual(context.report.state, "running")
                self.assertFalse(window.stop_report_btn.isEnabled())
                self.assertIn("退出清理", window.report_progress_label.text())
            finally:
                window.poll_timer.stop()
                window.close()


if __name__ == "__main__":
    unittest.main()
