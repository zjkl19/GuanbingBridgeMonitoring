from __future__ import annotations

import copy
import hashlib
import json
import shutil
import subprocess
import tempfile
import time
import unittest
import zipfile
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
PACKAGE_SCRIPT = REPO_ROOT / "scripts" / "package_workbench_github_release.ps1"
VERSION = "v1.8.1-rc3"
STABLE_VERSION = "v1.8.1"
OPERATOR_GUIDE_NAME = "\u4f7f\u7528\u8bf4\u660e.md"
CACHE_PREBUILD_STEM = "\u9884\u751f\u6210\u5206\u6790\u7f13\u5b58"
THRESHOLD_PREVIEW_STEM = "\u6253\u5f00\u66f2\u7ebf\u9884\u89c8\u5e76\u62d6\u7ebf\u8bbe\u7f6e"
BAND_THRESHOLD_STEM = "拖线设置上下限"
LOWER_BOX_RULE = "下侧框选取框中实际有限样本的最高值"
UPPER_BOX_RULE = "上侧框选取框中实际有限样本的最低值"
LOWER_DELETE_RULE = "删除严格低于该值的数据"
UPPER_DELETE_RULE = "删除严格高于该值的数据"
EQUALITY_RULE = "等于候选阈值的点保留"
CLEANUP_HIGH_RISK_RULE = "高风险、默认关闭"
CLEANUP_TASK_SCOPE_RULE = "只保存在当前任务方案中"
CLEANUP_CONFIG_ISOLATION_RULE = "不写入桥梁公共配置"
RESULT_LOCATION_STEM = "本次计算结果在哪里"
AUTO_PREVIEW_MATCH_STEM = "自动匹配当前任务曲线预览"
NO_JSON_STEM = "普通流程无需选择任何文件"
ADVANCED_PREVIEW_IMPORT_STEM = "从其他任务/项目导入参考曲线"
RESULT_STATS_DIR = "stats"
RESULT_LOGS_DIR = "run_logs"
REPORT_OUTPUT_STEM = "DOCX/PDF"
CLEANUP_LAYOUT = "jlj_daily_export"
CLEANUP_CONFIRMATION = "DELETE_VERIFIED_EXTRACTED_CSV"
GUIDE_FRAGMENTS = (
    CACHE_PREBUILD_STEM,
    THRESHOLD_PREVIEW_STEM,
    BAND_THRESHOLD_STEM,
    LOWER_BOX_RULE,
    UPPER_BOX_RULE,
    LOWER_DELETE_RULE,
    UPPER_DELETE_RULE,
    EQUALITY_RULE,
    CLEANUP_HIGH_RISK_RULE,
    CLEANUP_TASK_SCOPE_RULE,
    CLEANUP_CONFIG_ISOLATION_RULE,
    RESULT_LOCATION_STEM,
    AUTO_PREVIEW_MATCH_STEM,
    NO_JSON_STEM,
    ADVANCED_PREVIEW_IMPORT_STEM,
    RESULT_STATS_DIR,
    RESULT_LOGS_DIR,
    REPORT_OUTPUT_STEM,
    CLEANUP_LAYOUT,
    CLEANUP_CONFIRMATION,
)


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


class WorkbenchReleasePackagingTests(unittest.TestCase):
    def setUp(self) -> None:
        self.powershell = shutil.which("powershell.exe") or shutil.which("powershell")
        if self.powershell is None:
            self.skipTest("Windows PowerShell is unavailable")
        self.git = shutil.which("git.exe") or shutil.which("git")
        if self.git is None:
            self.skipTest("Git is unavailable")
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.repo = Path(self.temporary_directory.name)
        (self.repo / "scripts").mkdir(parents=True)
        (self.repo / "docs" / "releases").mkdir(parents=True)
        self.dist = self.repo / "dist" / "BridgeMonitoringWorkbench"
        self.dist.mkdir(parents=True)
        shutil.copy2(PACKAGE_SCRIPT, self.repo / "scripts" / PACKAGE_SCRIPT.name)
        (self.repo / "VERSION").write_text(VERSION, encoding="utf-8")
        (self.repo / "docs" / "releases" / f"{VERSION}.md").write_text(
            "# release fixture\n", encoding="utf-8"
        )
        self.fixture_version = VERSION
        self.smoke = {
            "ok": True,
            "version": self.fixture_version,
            "config_tab_count": 9,
            "manual_threshold_controls_available": True,
            "threshold_band_control_available": True,
            "lower_box_threshold_control_available": True,
            "upper_box_threshold_control_available": True,
            "offset_effective_range_seconds_available": True,
            "gap_override_column_count": 6,
            "unzip_settings_available": True,
            "analysis_result_location_visible": True,
            "analysis_result_open_control_available": True,
            "threshold_preview_auto_locator_available": True,
            "cache_source_cleanup_control_available": True,
            "cache_source_cleanup_checked": False,
            "cache_source_cleanup_default_off": True,
            "cache_source_cleanup_confirmation_empty": True,
            "cache_source_cleanup_confirmation_required": True,
            "cache_source_cleanup_confirmation_matches": False,
            "cache_source_cleanup_supported_data_layout": CLEANUP_LAYOUT,
            "cache_source_cleanup_supported_data_layouts": [
                "dated_folders",
                "hongtang_period",
                "jlj_daily_export",
            ],
            "cache_source_cleanup_current_layout_supported": True,
            "cache_source_cleanup_control_enabled": False,
            "cache_source_cleanup_task_option_present": False,
        }
        (self.dist / "workbench_smoke.json").write_text(
            json.dumps(self.smoke, ensure_ascii=False), encoding="utf-8"
        )
        (self.dist / "VERSION").write_text(VERSION, encoding="utf-8")
        (self.dist / "桥梁健康监测工作台.exe").write_bytes(b"fixture-executable")
        (self.dist / "asset.txt").write_text("fixture asset", encoding="utf-8")
        (self.dist / OPERATOR_GUIDE_NAME).write_text(
            "# Guide\n" + "\n".join(GUIDE_FRAGMENTS) + "\n",
            encoding="utf-8",
        )
        (self.repo / ".gitignore").write_text(
            "/*\n!/.gitignore\n!/VERSION\n!/scripts/\n!/docs/\n",
            encoding="utf-8",
        )
        subprocess.run([self.git, "init"], cwd=self.repo, check=True, capture_output=True)
        subprocess.run(
            [self.git, "config", "user.email", "workbench-tests@example.invalid"],
            cwd=self.repo,
            check=True,
            capture_output=True,
        )
        subprocess.run(
            [self.git, "config", "user.name", "Workbench Tests"],
            cwd=self.repo,
            check=True,
            capture_output=True,
        )
        subprocess.run(
            [self.git, "add", ".gitignore", "VERSION", "scripts", "docs"],
            cwd=self.repo,
            check=True,
            capture_output=True,
        )
        subprocess.run(
            [self.git, "commit", "-m", "Create release fixture"],
            cwd=self.repo,
            check=True,
            capture_output=True,
        )
        self.source_git_commit = subprocess.run(
            [self.git, "rev-parse", "HEAD"],
            cwd=self.repo,
            check=True,
            capture_output=True,
            text=True,
        ).stdout.strip()
        self.manifest = self._base_manifest()
        self._write_manifest()

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def _base_manifest(self) -> dict:
        inventory = []
        total_bytes = 0
        for path in sorted(self.dist.iterdir(), key=lambda value: value.name.casefold()):
            if path.name == "release_manifest.json":
                continue
            payload = path.read_bytes()
            inventory.append(
                {
                    "path": path.name,
                    "bytes": len(payload),
                    "sha256": hashlib.sha256(payload).hexdigest(),
                }
            )
            total_bytes += len(payload)
        return {
            "schema_version": 3,
            "source_git_commit": self.source_git_commit,
            "source_tree_clean": True,
            "version": self.fixture_version,
            "executable": "桥梁健康监测工作台.exe",
            "executable_sha256": _sha256(self.dist / "桥梁健康监测工作台.exe"),
            "auto_threshold_preview_runner_smoke": True,
            "analysis_runner_failure_exit_smoke": True,
            "analysis_runner_manifest_resilience_smoke": True,
            "analysis_runner_cache_cleanup_policy_smoke": True,
            "analysis_runner_cache_cleanup_policy": {
                "ok": True,
                "default_off": {"ok": True, "source_cleanup_enabled": False},
                "unsafe_policy": {
                    "ok": True,
                    "error_id": "BMS:CacheSourceCleanup:DedicatedTaskRequired",
                },
                "enabled_cleanup": {
                    "ok": True,
                    "configured_csv_deleted": True,
                    "unconfigured_csv_preserved": True,
                    "receipt_status": "committed",
                    "deleted_count": 1,
                },
                "enabled_cleanup_dated_folders": {
                    "ok": True,
                    "layout": "dated_folders",
                    "configured_csv_deleted": True,
                    "unconfigured_csv_preserved": True,
                    "source_archives_preserved": True,
                    "workbook_and_wim_preserved": True,
                    "receipt_status": "committed",
                    "deleted_count": 1,
                },
                "enabled_cleanup_hongtang_period": {
                    "ok": True,
                    "layout": "hongtang_period",
                    "configured_csv_deleted": True,
                    "unconfigured_csv_preserved": True,
                    "source_archives_preserved": True,
                    "workbook_and_wim_preserved": True,
                    "receipt_status": "committed",
                    "deleted_count": 1,
                },
            },
            "installed_profile_matrix_smoke": True,
            "invalid_cli_smoke": True,
            "task_history_smoke": True,
            "native_screenshot_smoke": True,
            "native_focus_smoke": True,
            "native_dpi_smoke": True,
            "native_font_smoke": True,
            "native_icon_smoke": True,
            "screenshot_mode": "native_windows",
            "native_gui_acceptance": {
                "foreground_window_matches": True,
                "focus_owned_by_process": True,
                "native_window_icon": True,
                "dpi_awareness_code": 2,
                "window_dpi": 120,
                "physical_width": 2018,
                "physical_height": 1122,
            },
            "operator_feature_contract_smoke": True,
            "operator_feature_contract_version": 4,
            "cache_source_cleanup_contract_smoke": True,
            "cache_source_cleanup_contract": {
                "default_off": True,
                "default_confirmation_empty": True,
                "default_task_option_absent": True,
                "layout_supported": True,
                "control_enabled_after_cache_selection": True,
                "confirmation_required": True,
                "confirmation_matches": True,
                "policy_complete": True,
                "saved_context_policy_complete": True,
                "saved_context_roundtrip": True,
                "restored_enabled": True,
                "restored_confirmation_matches": True,
                "task_option": {
                    "enabled": True,
                    "mode": "verified_extracted_csv",
                    "commit_scope": "day",
                    "recovery_policy": "verified_archive",
                    "confirmation": CLEANUP_CONFIRMATION,
                    "confirmed_at": "2026-07-16T00:00:00+08:00",
                },
            },
            "includes_analysis_runner": True,
            "report_runtime": "embedded_headless_worker",
            "standalone_report_builder_included": False,
            "includes_report_builder": True,
            "report_builder_context_smoke": True,
            "embedded_report_runtime_smoke": True,
            "embedded_report_job_smoke": True,
            "report_gate_contract_smoke": True,
            "report_visual_qc_smoke": True,
            "file_inventory_count": len(inventory),
            "file_count_excluding_manifest": len(inventory),
            "total_bytes_excluding_manifest": total_bytes,
            "file_inventory": inventory,
            "smoke": copy.deepcopy(self.smoke),
        }

    def _write_manifest(self) -> None:
        (self.dist / "release_manifest.json").write_text(
            json.dumps(self.manifest, ensure_ascii=False, indent=2), encoding="utf-8-sig"
        )

    def _write_smoke_and_refresh_manifest(self) -> None:
        smoke_path = self.dist / "workbench_smoke.json"
        smoke_path.write_text(
            json.dumps(self.smoke, ensure_ascii=False), encoding="utf-8"
        )
        self.manifest["smoke"] = copy.deepcopy(self.smoke)
        payload = smoke_path.read_bytes()
        for entry in self.manifest["file_inventory"]:
            if entry["path"] == smoke_path.name:
                entry["bytes"] = len(payload)
                entry["sha256"] = hashlib.sha256(payload).hexdigest()
                break
        self.manifest["total_bytes_excluding_manifest"] = sum(
            entry["bytes"] for entry in self.manifest["file_inventory"]
        )
        self._write_manifest()

    def _prepare_stable_fixture(self) -> None:
        self.fixture_version = STABLE_VERSION
        (self.repo / "VERSION").write_text(STABLE_VERSION, encoding="utf-8")
        (self.repo / "docs" / "releases" / f"{STABLE_VERSION}.md").write_text(
            "# stable release fixture\n", encoding="utf-8"
        )
        subprocess.run(
            [self.git, "add", "VERSION", "docs"],
            cwd=self.repo,
            check=True,
            capture_output=True,
        )
        subprocess.run(
            [self.git, "commit", "-m", "Prepare stable release fixture"],
            cwd=self.repo,
            check=True,
            capture_output=True,
        )
        self.source_git_commit = subprocess.run(
            [self.git, "rev-parse", "HEAD"],
            cwd=self.repo,
            check=True,
            capture_output=True,
            text=True,
        ).stdout.strip()
        self.smoke["version"] = STABLE_VERSION
        (self.dist / "workbench_smoke.json").write_text(
            json.dumps(self.smoke, ensure_ascii=False), encoding="utf-8"
        )
        (self.dist / "VERSION").write_text(STABLE_VERSION, encoding="utf-8")
        self.manifest = self._base_manifest()
        self._write_manifest()

    def _run(
        self,
        output: Path,
        *,
        version: str = VERSION,
        allow_development: bool = True,
    ) -> subprocess.CompletedProcess[str]:
        command = [
            self.powershell,
            "-NoLogo",
            "-NoProfile",
            "-NonInteractive",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            str(self.repo / "scripts" / PACKAGE_SCRIPT.name),
            "-Version",
            version,
            "-OutputDir",
            str(output),
            "-SkipBuild",
        ]
        if allow_development:
            command.append("-AllowDevelopmentVersion")
        return subprocess.run(
            command,
            cwd=self.repo,
            check=False,
            capture_output=True,
            encoding="utf-8",
            errors="replace",
            timeout=60,
        )

    def test_valid_fixture_is_packaged_with_exact_file_hashes(self) -> None:
        output = self.repo / "release-output"
        completed = self._run(output)
        self.assertEqual(0, completed.returncode, msg=completed.stderr)
        archive_path = output / f"BridgeMonitoringWorkbench-{VERSION}-win-x64.zip"
        self.assertTrue(archive_path.is_file())

        expected = {
            f"BridgeMonitoringWorkbench/{entry['path']}": (
                entry["bytes"],
                entry["sha256"],
            )
            for entry in self.manifest["file_inventory"]
        }
        manifest_bytes = (self.dist / "release_manifest.json").read_bytes()
        expected["BridgeMonitoringWorkbench/release_manifest.json"] = (
            len(manifest_bytes),
            hashlib.sha256(manifest_bytes).hexdigest(),
        )
        with zipfile.ZipFile(archive_path) as archive:
            self.assertEqual(set(expected), set(archive.namelist()))
            for name, (expected_bytes, expected_hash) in expected.items():
                payload = archive.read(name)
                self.assertEqual(expected_bytes, len(payload), name)
                self.assertEqual(expected_hash, hashlib.sha256(payload).hexdigest(), name)
        self.assertFalse((output / ".workbench_release_package.lock").exists())

    def test_stable_release_accepts_only_a_clean_commit_bound_fixture(self) -> None:
        self._prepare_stable_fixture()
        completed = self._run(
            self.repo / "stable-release-output",
            version=STABLE_VERSION,
            allow_development=False,
        )
        self.assertEqual(0, completed.returncode, msg=completed.stderr)
        publication = json.loads(
            (
                self.repo
                / "stable-release-output"
                / f"publish_{STABLE_VERSION}.json"
            ).read_text(encoding="utf-8")
        )
        self.assertEqual(self.source_git_commit, publication["source_git_commit"])
        self.assertIs(True, publication["source_tree_clean"])

    def test_stable_release_rejects_a_dirty_working_tree_before_packaging(self) -> None:
        self._prepare_stable_fixture()
        with (self.repo / "VERSION").open("a", encoding="utf-8") as stream:
            stream.write("\n")
        completed = self._run(
            self.repo / "dirty-stable-output",
            version=STABLE_VERSION,
            allow_development=False,
        )
        self.assertNotEqual(0, completed.returncode)
        self.assertIn("Stable releases require a clean Git working tree", completed.stderr)

    def test_development_release_can_record_an_explicit_dirty_source_tree(self) -> None:
        with (self.repo / "VERSION").open("a", encoding="utf-8") as stream:
            stream.write("\n")
        self.manifest["source_tree_clean"] = False
        self._write_manifest()
        completed = self._run(self.repo / "dirty-development-output")
        self.assertEqual(0, completed.returncode, msg=completed.stderr)
        publication = json.loads(
            (
                self.repo
                / "dirty-development-output"
                / f"publish_{VERSION}.json"
            ).read_text(encoding="utf-8")
        )
        self.assertEqual(self.source_git_commit, publication["source_git_commit"])
        self.assertIs(False, publication["source_tree_clean"])

    def test_release_manifest_source_binding_fails_closed(self) -> None:
        baseline = copy.deepcopy(self.manifest)
        cases = {
            "missing_commit": (
                lambda payload: payload.pop("source_git_commit"),
                "missing source_git_commit",
            ),
            "missing_clean": (
                lambda payload: payload.pop("source_tree_clean"),
                "missing source_tree_clean",
            ),
            "invalid_commit": (
                lambda payload: payload.__setitem__("source_git_commit", "ABC123"),
                "lowercase 40-character Git commit",
            ),
            "different_commit": (
                lambda payload: payload.__setitem__("source_git_commit", "0" * 40),
                "source commit differs from the current Git HEAD",
            ),
            "string_clean": (
                lambda payload: payload.__setitem__("source_tree_clean", "true"),
                "must be the Boolean value",
            ),
            "wrong_clean_state": (
                lambda payload: payload.__setitem__("source_tree_clean", False),
                "must be the Boolean value True",
            ),
        }
        for name, (mutate, expected_message) in cases.items():
            with self.subTest(name=name):
                self.manifest = copy.deepcopy(baseline)
                mutate(self.manifest)
                self._write_manifest()
                completed = self._run(self.repo / f"source-binding-{name}")
                self.assertNotEqual(0, completed.returncode)
                self.assertIn(expected_message, completed.stderr)

    def test_operator_guide_is_required(self) -> None:
        (self.dist / OPERATOR_GUIDE_NAME).unlink()
        completed = self._run(self.repo / "missing-operator-guide")
        self.assertNotEqual(0, completed.returncode)
        self.assertIn("Operator guide not found", completed.stderr)

    def test_operator_guide_requires_each_workflow_stem(self) -> None:
        for index, missing in enumerate(GUIDE_FRAGMENTS):
            with self.subTest(missing=missing):
                content = "# Guide\n" + "\n".join(
                    fragment for fragment in GUIDE_FRAGMENTS if fragment != missing
                )
                (self.dist / OPERATOR_GUIDE_NAME).write_text(
                    content,
                    encoding="utf-8",
                )
                completed = self._run(self.repo / f"missing-guide-fragment-{index}")
                self.assertNotEqual(0, completed.returncode)
                self.assertIn(
                    "Operator guide is missing required user workflow text",
                    completed.stderr,
                )

    def test_output_directory_inside_dist_is_rejected_before_creation(self) -> None:
        output = self.dist / "nested" / "release"
        completed = self._run(output)
        self.assertNotEqual(0, completed.returncode)
        self.assertIn("outside the workbench distribution", completed.stderr)
        self.assertFalse(output.exists())

    def test_output_directory_trailing_space_alias_is_rejected(self) -> None:
        output = Path(f"{self.dist} ") / "child"
        completed = self._run(output)
        self.assertNotEqual(0, completed.returncode)
        self.assertIn("segment ending in a space or dot", completed.stderr)
        self.assertFalse((self.dist / "child").exists())

    def test_output_directory_reparse_point_is_rejected(self) -> None:
        target = self.repo / "actual-output"
        target.mkdir()
        junction = self.repo / "junction-output"
        completed_link = subprocess.run(
            ["cmd.exe", "/d", "/c", "mklink", "/J", str(junction), str(target)],
            check=False,
            capture_output=True,
            text=True,
            timeout=15,
        )
        if completed_link.returncode != 0:
            self.skipTest(f"unable to create a test junction: {completed_link.stderr}")
        try:
            completed = self._run(junction)
            self.assertNotEqual(0, completed.returncode)
            self.assertIn("contains a reparse point", completed.stderr)
        finally:
            if junction.exists():
                junction.rmdir()

    def test_release_gate_requires_exact_boolean_types_and_schema(self) -> None:
        cases = (
            ("native_screenshot_smoke", "true", "must be the Boolean value"),
            ("native_focus_smoke", "true", "must be the Boolean value"),
            ("native_dpi_smoke", 1, "must be the Boolean value"),
            ("standalone_report_builder_included", 0, "must be the Boolean value"),
            ("schema_version", "3", "must be an integer"),
            ("schema_version", 4, "schema must be exactly 3"),
        )
        for index, (field, value, expected_message) in enumerate(cases):
            with self.subTest(field=field, value=value):
                self.manifest = self._base_manifest()
                self.manifest[field] = value
                self._write_manifest()
                completed = self._run(self.repo / f"invalid-{index}")
                self.assertNotEqual(0, completed.returncode)
                self.assertIn(expected_message, completed.stderr)

    def test_threshold_entry_smoke_fields_are_individually_required_true_booleans(self) -> None:
        fields = (
            "threshold_band_control_available",
            "lower_box_threshold_control_available",
            "upper_box_threshold_control_available",
        )
        baseline_smoke = copy.deepcopy(self.smoke)
        for index, field in enumerate(fields):
            for suffix, value in (("false", False), ("string", "true"), ("missing", None)):
                with self.subTest(field=field, value=value):
                    self.smoke = copy.deepcopy(baseline_smoke)
                    self.manifest = self._base_manifest()
                    if suffix == "missing":
                        self.smoke.pop(field)
                    else:
                        self.smoke[field] = value
                    self._write_smoke_and_refresh_manifest()
                    completed = self._run(
                        self.repo / f"invalid-threshold-smoke-{index}-{suffix}"
                    )
                    self.assertNotEqual(0, completed.returncode)
                    self.assertIn(field, completed.stderr)

    def test_result_discovery_smoke_fields_are_individually_required_true_booleans(self) -> None:
        fields = (
            "analysis_result_location_visible",
            "analysis_result_open_control_available",
            "threshold_preview_auto_locator_available",
        )
        baseline_smoke = copy.deepcopy(self.smoke)
        for index, field in enumerate(fields):
            for suffix, value in (("false", False), ("string", "true"), ("missing", None)):
                with self.subTest(field=field, value=value):
                    self.smoke = copy.deepcopy(baseline_smoke)
                    self.manifest = self._base_manifest()
                    if suffix == "missing":
                        self.smoke.pop(field)
                    else:
                        self.smoke[field] = value
                    self._write_smoke_and_refresh_manifest()
                    completed = self._run(
                        self.repo / f"invalid-result-discovery-smoke-{index}-{suffix}"
                    )
                    self.assertNotEqual(0, completed.returncode)
                    self.assertIn(field, completed.stderr)

    def test_native_gui_evidence_is_strictly_validated(self) -> None:
        cases = (
            ("foreground_window_matches", False, "must be the Boolean value True"),
            ("focus_owned_by_process", "true", "must be the Boolean value"),
            ("native_window_icon", False, "must be the Boolean value True"),
            ("dpi_awareness_code", 1, "acceptance evidence is incomplete"),
            ("window_dpi", 95, "acceptance evidence is incomplete"),
            ("physical_width", 999, "acceptance evidence is incomplete"),
            ("physical_height", 699, "acceptance evidence is incomplete"),
        )
        for index, (field, value, expected_message) in enumerate(cases):
            with self.subTest(field=field, value=value):
                self.manifest = self._base_manifest()
                self.manifest["native_gui_acceptance"][field] = value
                self._write_manifest()
                completed = self._run(self.repo / f"invalid-native-gui-{index}")
                self.assertNotEqual(0, completed.returncode)
                self.assertIn(expected_message, completed.stderr)

    def test_cache_cleanup_release_evidence_fails_closed(self) -> None:
        baseline = copy.deepcopy(self.manifest)
        mutations = {
            "default_not_frozen": lambda payload: payload[
                "cache_source_cleanup_contract"
            ].__setitem__("default_off", False),
            "wrong_confirmation": lambda payload: payload[
                "cache_source_cleanup_contract"
            ]["task_option"].__setitem__("confirmation", "DELETE"),
            "unconfigured_csv_not_preserved": lambda payload: payload[
                "analysis_runner_cache_cleanup_policy"
            ]["enabled_cleanup"].__setitem__("unconfigured_csv_preserved", False),
            "dated_folders_archive_not_preserved": lambda payload: payload[
                "analysis_runner_cache_cleanup_policy"
            ]["enabled_cleanup_dated_folders"].__setitem__(
                "source_archives_preserved", False
            ),
            "hongtang_wrong_layout": lambda payload: payload[
                "analysis_runner_cache_cleanup_policy"
            ]["enabled_cleanup_hongtang_period"].__setitem__(
                "layout", "dated_folders"
            ),
            "manifest_resilience_missing": lambda payload: payload.pop(
                "analysis_runner_manifest_resilience_smoke"
            ),
        }
        for name, mutate in mutations.items():
            with self.subTest(name=name):
                self.manifest = copy.deepcopy(baseline)
                mutate(self.manifest)
                self._write_manifest()
                completed = self._run(self.repo / f"reject-{name}")
                self.assertNotEqual(0, completed.returncode)

    def test_executable_must_be_a_safe_inventory_bound_path(self) -> None:
        outside = self.repo / "outside.exe"
        outside.write_bytes(b"fixture-executable")
        self.manifest["executable"] = "../outside.exe"
        self._write_manifest()
        completed = self._run(self.repo / "unsafe-executable")
        self.assertNotEqual(0, completed.returncode)
        self.assertIn("Unsafe relative package path", completed.stderr)

    def test_singleton_array_cannot_impersonate_a_string_field(self) -> None:
        for field in ("version", "executable", "executable_sha256", "screenshot_mode"):
            with self.subTest(field=field):
                self.manifest = self._base_manifest()
                self.manifest[field] = [self.manifest[field]]
                self._write_manifest()
                completed = self._run(self.repo / f"array-{field}")
                self.assertNotEqual(0, completed.returncode)
                self.assertIn("must be a string", completed.stderr)

    def test_failed_gate_preserves_existing_publication_assets(self) -> None:
        output = self.repo / "existing-output"
        output.mkdir()
        archive = output / f"BridgeMonitoringWorkbench-{VERSION}-win-x64.zip"
        checksum = Path(f"{archive}.sha256")
        publication = output / f"publish_{VERSION}.json"
        sentinels = {
            archive: b"old archive",
            checksum: b"old checksum",
            publication: b"old publication",
        }
        for path, payload in sentinels.items():
            path.write_bytes(payload)

        self.manifest["native_screenshot_smoke"] = "true"
        self._write_manifest()
        completed = self._run(output)
        self.assertNotEqual(0, completed.returncode)
        for path, payload in sentinels.items():
            self.assertEqual(payload, path.read_bytes(), path.name)
        self.assertEqual([], list(output.glob(".*.tmp")))

    def test_existing_publication_symlink_is_rejected(self) -> None:
        output = self.repo / "symlink-output"
        output.mkdir()
        target = self.repo / "publication-target.bin"
        target.write_bytes(b"do not replace")
        archive = output / f"BridgeMonitoringWorkbench-{VERSION}-win-x64.zip"
        completed_link = subprocess.run(
            ["cmd.exe", "/d", "/c", "mklink", str(archive), str(target)],
            check=False,
            capture_output=True,
            text=True,
            timeout=15,
        )
        if completed_link.returncode != 0:
            self.skipTest(f"unable to create a test file symlink: {completed_link.stderr}")
        try:
            completed = self._run(output)
            self.assertNotEqual(0, completed.returncode)
            self.assertIn("Publication destination is a reparse point", completed.stderr)
            self.assertEqual(b"do not replace", target.read_bytes())
        finally:
            archive.unlink(missing_ok=True)

    def test_concurrent_packager_lock_fails_closed(self) -> None:
        output = self.repo / "locked-output"
        output.mkdir()
        lock_path = output / ".workbench_release_package.lock"
        ready_path = output / ".lock-ready"
        holder_script = output / "hold_lock.ps1"
        holder_script.write_text(
            f'''$stream = [IO.File]::Open(
    "{str(lock_path).replace(chr(34), chr(34) * 2)}",
    [IO.FileMode]::OpenOrCreate,
    [IO.FileAccess]::ReadWrite,
    [IO.FileShare]::None
)
try {{
    [IO.File]::WriteAllText("{str(ready_path).replace(chr(34), chr(34) * 2)}", "ready")
    Start-Sleep -Seconds 30
}}
finally {{
    $stream.Dispose()
}}
''',
            encoding="utf-8-sig",
        )
        creation_flags = getattr(subprocess, "CREATE_NO_WINDOW", 0)
        holder = subprocess.Popen(
            [
                self.powershell,
                "-NoLogo",
                "-NoProfile",
                "-NonInteractive",
                "-ExecutionPolicy",
                "Bypass",
                "-File",
                str(holder_script),
            ],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            creationflags=creation_flags,
        )
        try:
            deadline = time.monotonic() + 5
            while not ready_path.exists() and time.monotonic() < deadline:
                time.sleep(0.05)
            self.assertTrue(ready_path.exists(), "lock holder did not become ready")
            completed = self._run(output)
            self.assertNotEqual(0, completed.returncode)
            self.assertIn("Another workbench release packaging process", completed.stderr)
        finally:
            holder.terminate()
            try:
                holder.wait(timeout=5)
            except subprocess.TimeoutExpired:
                holder.kill()
                holder.wait(timeout=5)

    def test_publication_set_rolls_back_earlier_replacements(self) -> None:
        package_source = PACKAGE_SCRIPT.read_text(encoding="utf-8-sig")
        function_start = package_source.index("function Publish-VerifiedFileSet")
        function_end = package_source.index("\n$repo =", function_start)
        helper_source = package_source[function_start:function_end]
        root = self.repo / "rollback-fixture"
        root.mkdir()
        script_path = root / "exercise_rollback.ps1"
        script_path.write_text(
            f'''$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0
{helper_source}
$root = "{str(root).replace(chr(34), chr(34) * 2)}"
$temp1 = Join-Path $root "temp1"
$temp2 = Join-Path $root "temp2"
$temp3 = Join-Path $root "temp3"
$dest1 = Join-Path $root "dest1"
$dest2 = Join-Path $root "dest2"
$blockedDestination = Join-Path $root "blocked"
[IO.File]::WriteAllText($temp1, "new1")
[IO.File]::WriteAllText($temp2, "new2")
[IO.File]::WriteAllText($temp3, "new3")
[IO.File]::WriteAllText($dest1, "old1")
[IO.File]::WriteAllText($dest2, "old2")
[IO.Directory]::CreateDirectory($blockedDestination) | Out-Null
try {{
    Publish-VerifiedFileSet @(
        [pscustomobject]@{{ temporary = $temp1; destination = $dest1 }},
        [pscustomobject]@{{ temporary = $temp2; destination = $dest2 }},
        [pscustomobject]@{{ temporary = $temp3; destination = $blockedDestination }}
    )
    exit 91
}}
catch {{
    if ([IO.File]::ReadAllText($dest1) -ne "old1" `
            -or [IO.File]::ReadAllText($dest2) -ne "old2") {{
        Write-Error "publication rollback did not restore prior assets"
        exit 92
    }}
}}
exit 0
''',
            encoding="utf-8-sig",
        )
        completed = subprocess.run(
            [
                self.powershell,
                "-NoLogo",
                "-NoProfile",
                "-NonInteractive",
                "-ExecutionPolicy",
                "Bypass",
                "-File",
                str(script_path),
            ],
            check=False,
            capture_output=True,
            encoding="utf-8",
            errors="replace",
            timeout=30,
        )
        self.assertEqual(
            0,
            completed.returncode,
            msg=f"stdout={completed.stdout}\nstderr={completed.stderr}",
        )


if __name__ == "__main__":
    unittest.main()
