from __future__ import annotations

import argparse
import ast
import os
import unittest
from pathlib import Path
from typing import Callable, Sequence


DEFAULT_TEST_DIRS = ("tests_py", "tests")


def build_suite(
    repo_root: Path,
    *,
    test_dirs: tuple[str, ...] = DEFAULT_TEST_DIRS,
    pattern: str = "test_*.py",
    loader: unittest.TestLoader | None = None,
) -> unittest.TestSuite:
    """Discover every maintained Python test location."""

    root = repo_root.resolve()
    selected_loader = loader or unittest.defaultTestLoader
    suite = unittest.TestSuite()
    for relative in test_dirs:
        start_dir = root / relative
        if not start_dir.is_dir():
            raise FileNotFoundError(f"Python test directory does not exist: {start_dir}")
        suite.addTests(
            selected_loader.discover(
                start_dir=str(start_dir),
                pattern=pattern,
                top_level_dir=str(root),
            )
        )
    return suite


def discover_pytest_function_nodes(
    repo_root: Path,
    *,
    test_dirs: tuple[str, ...] = DEFAULT_TEST_DIRS,
    pattern: str = "test_*.py",
) -> list[str]:
    """Return pytest node ids for module-level test functions only.

    ``unittest`` discovery imports pytest-style modules but does not execute
    their module-level functions.  Selecting only those function node ids lets
    pytest expand parametrized cases without rerunning ``unittest.TestCase``
    classes from the same maintained test roots.  A module that defines the
    standard ``load_tests`` hook remains entirely unittest-owned because that
    hook may already wrap its top-level functions in ``FunctionTestCase``.
    """

    root = repo_root.resolve()
    nodes: list[str] = []
    for relative in test_dirs:
        start_dir = root / relative
        if not start_dir.is_dir():
            raise FileNotFoundError(f"Python test directory does not exist: {start_dir}")
        for path in sorted(start_dir.glob(pattern)):
            if not path.is_file():
                continue
            tree = ast.parse(path.read_text(encoding="utf-8-sig"), filename=str(path))
            if any(
                isinstance(statement, (ast.FunctionDef, ast.AsyncFunctionDef))
                and statement.name == "load_tests"
                for statement in tree.body
            ):
                continue
            relative_path = path.relative_to(root).as_posix()
            for statement in tree.body:
                if isinstance(statement, (ast.FunctionDef, ast.AsyncFunctionDef)) and statement.name.startswith("test_"):
                    nodes.append(f"{relative_path}::{statement.name}")
    return nodes


def run_pytest_function_nodes(
    repo_root: Path,
    nodes: Sequence[str],
    *,
    verbosity: int = 1,
    pytest_main: Callable[[list[str]], int] | None = None,
) -> int:
    """Run only module-level pytest functions and return pytest's exit code."""

    if not nodes:
        return 0
    if pytest_main is None:
        try:
            import pytest
        except ModuleNotFoundError as exc:  # pragma: no cover - dependency gate
            raise RuntimeError(
                "pytest is required for module-level tests; install "
                "reporting/requirements-test.txt"
            ) from exc
        pytest_main = pytest.main
    pytest_args = ["-vv"] if verbosity >= 2 else ["-q"]
    pytest_args.extend(nodes)
    previous_cwd = Path.cwd()
    try:
        # Relative node ids are deliberate: they keep output readable and let
        # coverage.py trace pytest in this same interpreter process.
        os.chdir(repo_root)
        return int(pytest_main(pytest_args))
    finally:
        os.chdir(previous_cwd)


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Run all maintained Guanbing Python tests.")
    parser.add_argument("--repo-root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--verbosity", type=int, choices=(0, 1, 2), default=1)
    parser.add_argument("--pattern", default="test_*.py")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    pytest_nodes = discover_pytest_function_nodes(args.repo_root, pattern=args.pattern)
    suite = build_suite(args.repo_root, pattern=args.pattern)
    print(f"[unittest] running {suite.countTestCases()} discovered case(s)", flush=True)
    result = unittest.TextTestRunner(verbosity=args.verbosity).run(suite)
    print(f"[pytest] running {len(pytest_nodes)} module-level function node(s)", flush=True)
    pytest_exit = run_pytest_function_nodes(
        args.repo_root,
        pytest_nodes,
        verbosity=args.verbosity,
    )
    return 0 if result.wasSuccessful() and pytest_exit == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
