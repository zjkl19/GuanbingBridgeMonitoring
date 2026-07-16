from __future__ import annotations

import configparser
import io
import importlib.util
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]


def _load_runner_module():
    path = ROOT / "scripts" / "run_python_tests.py"
    spec = importlib.util.spec_from_file_location("guanbing_python_test_runner", path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class CoverageEntrypointTests(unittest.TestCase):
    def test_python_test_runner_discovers_both_maintained_roots(self) -> None:
        module = _load_runner_module()
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            for name in ("tests_py", "tests"):
                test_dir = root / name
                test_dir.mkdir()
                (test_dir / "__init__.py").write_text("", encoding="utf-8")
                (test_dir / "test_probe.py").write_text(
                    "import unittest\n"
                    "class Probe(unittest.TestCase):\n"
                    "    def test_ok(self): self.assertTrue(True)\n",
                    encoding="utf-8",
                )
            suite = module.build_suite(root)
            self.assertEqual(suite.countTestCases(), 2)

    def test_python_test_runner_selects_only_module_level_pytest_functions(self) -> None:
        module = _load_runner_module()
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            test_py = root / "unit_py"
            tests = root / "unit_report"
            test_py.mkdir()
            tests.mkdir()
            (test_py / "__init__.py").write_text("", encoding="utf-8")
            (tests / "__init__.py").write_text("", encoding="utf-8")
            (test_py / "test_mixed.py").write_text(
                "import unittest\n"
                "def test_pytest_only(): assert True\n"
                "class UnitProbe(unittest.TestCase):\n"
                "    def test_unittest_only(self): self.assertTrue(True)\n",
                encoding="utf-8",
            )
            (tests / "test_report_probe.py").write_text(
                "import unittest\n"
                "def test_report_unittest_wrapped(): assert True\n"
                "def load_tests(loader, tests, pattern):\n"
                "    return unittest.TestSuite([unittest.FunctionTestCase(test_report_unittest_wrapped)])\n",
                encoding="utf-8",
            )

            test_dirs = ("unit_py", "unit_report")
            suite = module.build_suite(root, test_dirs=test_dirs)
            nodes = module.discover_pytest_function_nodes(root, test_dirs=test_dirs)

            self.assertEqual(suite.countTestCases(), 2)
            self.assertEqual(
                nodes,
                ["unit_py/test_mixed.py::test_pytest_only"],
            )

    def test_python_test_runner_invokes_pytest_nodes_without_subprocess(self) -> None:
        module = _load_runner_module()
        captured: list[list[str]] = []

        def fake_pytest_main(args: list[str]) -> int:
            captured.append(args)
            return 0

        nodes = ["tests_py/test_probe.py::test_one"]
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            exit_code = module.run_pytest_function_nodes(
                root,
                nodes,
                verbosity=2,
                pytest_main=fake_pytest_main,
            )

        self.assertEqual(exit_code, 0)
        self.assertEqual(captured, [["-vv", *nodes]])

    def test_python_test_runner_propagates_pytest_failure(self) -> None:
        module = _load_runner_module()
        with patch.object(module, "discover_pytest_function_nodes", return_value=["x.py::test_bad"]), patch.object(
            module, "build_suite", return_value=unittest.TestSuite()
        ), patch.object(module, "run_pytest_function_nodes", return_value=1):
            with redirect_stdout(io.StringIO()):
                self.assertEqual(module.main(["--repo-root", str(ROOT), "--verbosity", "0"]), 1)

    def test_test_requirements_declare_pytest(self) -> None:
        requirements = (ROOT / "reporting" / "requirements-test.txt").read_text(encoding="utf-8")
        self.assertRegex(requirements, r"(?m)^pytest[^#\r\n]*$")

    def test_python_coverage_config_enables_branch_measurement(self) -> None:
        parser = configparser.ConfigParser()
        parser.read(ROOT / ".coveragerc", encoding="utf-8")
        self.assertTrue(parser.getboolean("run", "branch"))
        source = parser.get("run", "source")
        self.assertIn("workbench", source)
        self.assertIn("reporting", source)

    def test_matlab_coverage_script_collects_condition_metric_and_cobertura(self) -> None:
        source = (ROOT / "scripts" / "run_matlab_coverage.m").read_text(encoding="utf-8")
        self.assertIn("CodeCoveragePlugin.forFolder(sourceFolders", source)
        for folder in ("+bms", "analysis", "pipeline", "ui", "config", "scripts"):
            self.assertIn(f"fullfile(repo, '{folder}')", source)
        self.assertIn("'IncludingSubfolders', true", source)
        self.assertIn("'MetricLevel', 'condition'", source)
        self.assertIn("CoberturaFormat(coberturaPath)", source)
        self.assertIn("matlab-coverage-summary.json", source)

    def test_release_and_smoke_entrypoints_use_the_shared_python_runner(self) -> None:
        for relative in ("scripts/run_ci_smoke.ps1", "scripts/run_release_health_check.ps1"):
            source = (ROOT / relative).read_text(encoding="utf-8")
            self.assertIn("scripts\\run_python_tests.py", source)
            self.assertNotIn('"discover", "tests_py"', source)
        ci_source = (ROOT / "scripts/run_ci_smoke.ps1").read_text(encoding="utf-8")
        self.assertIn("reporting\\.venv\\Scripts\\python.exe", ci_source)
        self.assertIn("& $projectPython .\\scripts\\run_python_tests.py", ci_source)

    def test_coverage_orchestrator_supports_a_narrow_instrumentation_smoke(self) -> None:
        source = (ROOT / "scripts" / "run_coverage_baseline.ps1").read_text(encoding="utf-8")
        self.assertIn('[string]$PythonPattern = "test_*.py"', source)
        self.assertIn("--pattern $PythonPattern", source)
        self.assertIn('$env:COVERAGE_FILE = Join-Path $OutputRoot ".coverage"', source)


if __name__ == "__main__":
    unittest.main()
