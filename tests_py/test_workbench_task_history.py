from __future__ import annotations

import json
import os
import tempfile
import unittest
from pathlib import Path
from shutil import copy2

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

from PySide6.QtWidgets import QApplication

from workbench.models import JobContext
from workbench.task_history import TaskHistoryIndex, _analysis_detail, _report_detail, _state
from workbench.task_history_tab import TaskHistoryWidget


ROOT = Path(__file__).resolve().parents[1]


class TaskHistoryIndexTests(unittest.TestCase):
    def _context(self, root: Path, job_id: str = "task_one", bridge_id: str = "guanbing") -> JobContext:
        data_root = root / "data"
        data_root.mkdir(parents=True, exist_ok=True)
        config = root / "config.json"
        if not config.exists():
            copy2(ROOT / "config" / "default_config.json", config)
        context = JobContext.create(
            project_root=ROOT,
            bridge_id=bridge_id,
            bridge_name="管柄大桥",
            data_root=data_root,
            start_date="2026-06-01",
            end_date="2026-06-30",
            config_path=config,
            selected_modules=["acceleration"],
            options={"run_acceleration": True},
            job_id=job_id,
        )
        context.write()
        return context

    def test_status_files_override_stale_context_and_completed_outputs_close(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            context = self._context(root)
            manifest = root / "manifest.json"
            report = root / "report.docx"
            manifest.write_text("{}", encoding="utf-8")
            report.write_bytes(b"docx")
            Path(context.analysis.status_path).write_text(
                json.dumps({
                    "status": "completed", "progress_fraction": 1,
                    "completed_modules": 1, "module_total": 1,
                    "manifest_path": str(manifest),
                }),
                encoding="utf-8",
            )
            Path(context.report.status_path).write_text(
                json.dumps({
                    "state": "completed", "stage": "completed",
                    "result_path": context.report.result_path,
                }),
                encoding="utf-8",
            )
            Path(context.report.result_path).write_text(
                json.dumps({
                    "state": "completed", "report_path": str(report),
                    "qc": {"status": "passed"},
                }),
                encoding="utf-8",
            )
            entry = TaskHistoryIndex(("guanbing",)).inspect(context.context_path)
            self.assertEqual(entry.analysis_state, "completed")
            self.assertEqual(entry.report_state, "completed")
            self.assertEqual(entry.health, "ready")
            self.assertTrue(entry.can_restore)
            self.assertIn("100%", entry.analysis_detail)

    def test_config_drift_is_visible_warning_but_remains_restorable(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            context = self._context(root)
            Path(context.config_path).write_text("{}", encoding="utf-8")
            entry = TaskHistoryIndex(("guanbing",)).inspect(context.context_path)
            self.assertEqual(entry.health, "warning")
            self.assertTrue(entry.can_restore)
            self.assertIn("配置SHA256已变化", entry.issues)

    def test_layer_change_is_detected_by_same_history_index_instance(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            data_root = root / "data"
            data_root.mkdir()
            layer = root / "layer.json"
            layer.write_text('{"value":1}', encoding="utf-8")
            config = root / "project.json"
            config.write_text('{"layers":["layer.json"]}', encoding="utf-8")
            context = JobContext.create(
                project_root=ROOT,
                bridge_id="guanbing",
                bridge_name="管柄大桥",
                data_root=data_root,
                start_date="2026-06-01",
                end_date="2026-06-30",
                config_path=config,
                selected_modules=["acceleration"],
                options={"run_acceleration": True},
                job_id="layered_history",
            )
            context.write()
            index = TaskHistoryIndex(("guanbing",))
            self.assertNotIn("配置SHA256已变化", index.inspect(context.context_path).issues)

            layer.write_text('{"value":2}', encoding="utf-8")

            self.assertIn("配置SHA256已变化", index.inspect(context.context_path).issues)

    def test_unknown_bridge_and_invalid_json_are_not_restorable(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            unknown = self._context(root, bridge_id="unknown")
            unknown_entry = TaskHistoryIndex(("guanbing",)).inspect(unknown.context_path)
            self.assertEqual(unknown_entry.health, "invalid")
            self.assertFalse(unknown_entry.can_restore)
            broken = root / "broken" / "job_context.json"
            broken.parent.mkdir()
            broken.write_text("{", encoding="utf-8")
            broken_entry = TaskHistoryIndex(("guanbing",)).inspect(broken)
            self.assertEqual(broken_entry.health, "invalid")
            self.assertFalse(broken_entry.can_restore)

    def test_discovery_is_bounded_to_direct_job_children_and_explicit_paths(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            first = self._context(root, "first")
            nested = first.context_path.parent / "nested" / "job_context.json"
            nested.parent.mkdir()
            nested.write_bytes(first.context_path.read_bytes())
            external = root / "external" / "job_context.json"
            external.parent.mkdir()
            external.write_bytes(first.context_path.read_bytes())
            entries = TaskHistoryIndex(("guanbing",)).discover(
                data_roots=(Path(first.data_root),), extra_paths=(external,)
            )
            self.assertEqual({entry.context_path for entry in entries}, {first.context_path, external.resolve()})
            self.assertNotIn(nested.resolve(), {entry.context_path for entry in entries})

    def test_shared_status_fixture_matches_matlab_contract(self) -> None:
        payload = json.loads(
            (ROOT / "tests" / "fixtures" / "workbench_task_history_contract.json").read_text(encoding="utf-8")
        )
        analysis = payload["analysis_status"]
        report = payload["report_status"]
        report_result = payload["report_result"]
        with tempfile.TemporaryDirectory() as folder:
            context = self._context(Path(folder))
            self.assertEqual(_state(analysis, "draft", "status", "state"), "running")
            self.assertEqual(_analysis_detail(analysis), "索力加速度；7/11；64%")
            merged = dict(report_result)
            merged.update(report)
            self.assertEqual(_report_detail(merged, context), "质量检查：通过")


class TaskHistoryWidgetTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.app = QApplication.instance() or QApplication([])

    def test_demo_filter_selection_and_restore_signal(self) -> None:
        widget = TaskHistoryWidget(("guanbing", "hongtang", "zhishan"))
        restored: list[str] = []
        widget.restore_requested.connect(restored.append)
        try:
            widget.load_demo()
            self.assertEqual(widget.table.columnCount(), 8)
            self.assertEqual(widget.table.rowCount(), 4)
            widget.search_edit.setText("洪塘")
            self.assertEqual(widget.table.rowCount(), 1)
            widget.table.selectRow(0)
            self.assertTrue(widget.restore_button.isEnabled())
            widget._restore()
            self.assertEqual(len(restored), 1)
            widget.search_edit.clear()
            widget.state_filter.setCurrentIndex(widget.state_filter.findData("invalid"))
            widget.table.selectRow(0)
            self.assertFalse(widget.restore_button.isEnabled())
        finally:
            widget.close()


if __name__ == "__main__":
    unittest.main()
