from __future__ import annotations

import configparser
import importlib.util
import tempfile
import unittest
from pathlib import Path


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
