from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from workbench.analysis import AnalysisLauncher, AnalysisRequestBuilder, Executor, ExecutorResolver, read_analysis_status
from workbench.models import JobContext
from workbench.modules import options_for_modules


class _FakeProcess:
    pid = 24680


class WorkbenchAnalysisTests(unittest.TestCase):
    def _context(self, root: Path) -> JobContext:
        config = root / "config.json"
        config.write_text('{"plot_common":{"gap_mode":"connect"}}', encoding="utf-8")
        data_root = root / "data"
        data_root.mkdir()
        return JobContext.create(
            project_root=root,
            bridge_id="unit",
            bridge_name="测试桥",
            data_root=data_root,
            start_date="2026-01-01",
            end_date="2026-01-02",
            config_path=config,
            selected_modules=["temperature", "acceleration"],
            options=options_for_modules(["temperature", "acceleration"]),
            job_id="analysis_unit",
        )

    def test_request_matches_matlab_run_request_contract(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            context = self._context(Path(folder))
            payload = AnalysisRequestBuilder().build(context)
            self.assertEqual(payload["data_root"], context.data_root)
            self.assertEqual(payload["async_run_id"], "analysis_unit")
            self.assertTrue(payload["options"]["doTemp"])
            self.assertTrue(payload["options"]["doAccel"])
            self.assertEqual(payload["config"]["plot_common"]["gap_mode"], "connect")
            self.assertEqual(payload["config"]["source"], context.config_path)

    def test_request_rejects_config_changed_after_job_creation(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            context = self._context(Path(folder))
            Path(context.config_path).write_text('{"changed":true}', encoding="utf-8")
            with self.assertRaisesRegex(RuntimeError, "Config changed"):
                AnalysisRequestBuilder().build(context)

    def test_matlab_command_quotes_paths_and_uses_batch_entry(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder) / "project's files"
            root.mkdir()
            context = self._context(root)
            matlab = root / "matlab.exe"
            matlab.write_bytes(b"fake")
            command = AnalysisLauncher(root).command(context, Executor("matlab_batch", matlab))
            self.assertEqual(command[1:4], ("-nosplash", "-nodesktop", "-batch"))
            self.assertIn("run_request_cli", command[4])
            self.assertIn("project''s files", command[4])

    def test_launcher_writes_request_status_and_context(self) -> None:
        calls: list[tuple[tuple[str, ...], dict]] = []

        def fake_popen(command, **kwargs):
            calls.append((tuple(command), kwargs))
            return _FakeProcess()

        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            context = self._context(root)
            runner = root / "BridgeAnalysisRunner.exe"
            runner.write_bytes(b"fake")
            result = AnalysisLauncher(root, popen=fake_popen).launch(context, Executor("compiled_runner", runner))
            self.assertEqual(result.pid, 24680)
            self.assertTrue(Path(context.analysis.request_path).is_file())
            self.assertTrue(Path(context.analysis.status_path).is_file())
            self.assertTrue(context.context_path.is_file())
            self.assertEqual(JobContext.read(context.context_path).analysis.pid, 24680)
            self.assertEqual(calls[0][0], (str(runner), context.analysis.request_path))

    def test_status_reader_handles_bom_and_corruption(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            context = self._context(Path(folder))
            status = Path(context.analysis.status_path)
            status.parent.mkdir(parents=True)
            status.write_text('\ufeff{"status":"completed","manifest_path":"x.json"}', encoding="utf-8")
            self.assertEqual(read_analysis_status(context)["status"], "completed")
            status.write_text("not json", encoding="utf-8")
            self.assertEqual(read_analysis_status(context)["status"], "status_read_failed")

    def test_executor_prefers_explicit_runner(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            runner = root / "runner.exe"
            runner.write_bytes(b"fake")
            executor = ExecutorResolver(root).resolve(runner=runner)
            self.assertEqual(executor.kind, "compiled_runner")
            self.assertEqual(executor.executable, runner.resolve())


if __name__ == "__main__":
    unittest.main()
